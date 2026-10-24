import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/investments/investment_models.dart';
import 'package:expensy/investments/investment_repository.dart';
import 'package:expensy/investments/investment_quotes.dart';

Investment asset({String id = 'asset'}) => Investment(
    id: id,
    name: 'Empresa Teste',
    assetClass: 'Ações',
    ticker: 'PETR4',
    priceMicros: 12000000,
    priceAt: DateTime(2026, 10, 1));
InvestmentOperation op(String id, String kind, int units, int cents,
        {int day = 1}) =>
    InvestmentOperation(
        id: id,
        investmentId: 'asset',
        kind: kind,
        quantity: units * investmentScale,
        cents: cents,
        date: DateTime(2026, 10, day),
        createdAt: DateTime(2026, 10, day));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InvestmentRepository repository;
  late Directory dir;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('nexo-investment-test-');
    await databaseFactory.setDatabasesPath(dir.path);
    repository = InvestmentRepository();
  });
  tearDownAll(() async {
    await DBHelper.close();
    await dir.delete(recursive: true);
  });
  setUp(() async {
    final db = await DBHelper.database;
    await db.delete('investment_operations');
    await db.delete('investments');
  });
  test('quantity input is exact, bounded and rejects ambiguous grouping', () {
    expect(parseInvestmentQuantity('0,000001'), 1);
    expect(parseInvestmentQuantity('12.345678'), 12345678);
    for (final text in [
      '1.234,56',
      '-1',
      'NaN',
      '1e3',
      '0',
      '0,0000001',
      '1000001'
    ]) {
      expect(parseInvestmentQuantity(text), isNull, reason: text);
    }
  });
  test('weighted cost, partial sale and dividends do not inflate return', () {
    final p = InvestmentPosition(asset(), [
      op('a', 'buy', 10, 10000),
      op('b', 'buy', 10, 20000, day: 2),
      op('c', 'sell', 5, 10000, day: 3),
      op('d', 'income', 0, 2000, day: 4)
    ]);
    expect(p.quantity, 15 * investmentScale);
    expect(p.cost, 22500);
    expect(p.realized, 2500);
    expect(p.value, 18000);
    expect(p.income, 2000);
    expect(p.unrealized, -4500);
    expect(p.result, 0);
  });
  test('full sale clears rounding residual; repurchase starts a new cost', () {
    final p = InvestmentPosition(asset(), [
      op('a', 'buy', 3, 100),
      op('b', 'sell', 1, 40, day: 2),
      op('c', 'sell', 2, 80, day: 3)
    ]);
    expect(p.quantity, 0);
    expect(p.cost, 0);
    expect(p.realized, 20);
    final again = InvestmentPosition(
        asset(), [...p.operations, op('d', 'buy', 2, 200, day: 4)]);
    expect(again.cost, 200);
    expect(again.realized, 20);
  });
  test('out of order operations replay by date; historical oversell is blocked',
      () {
    expect(
        () => InvestmentPosition(asset(), [
              op('b', 'buy', 10, 1000, day: 3),
              op('a', 'sell', 1, 100, day: 1)
            ]),
        throwsFormatException);
    expect(
        InvestmentPosition(asset(), [
          op('b', 'sell', 1, 100, day: 3),
          op('a', 'buy', 10, 1000)
        ]).quantity,
        9 * investmentScale);
  });
  test(
      'migration from 23 preserves all old data and backup supports both versions',
      () async {
    final db = await DBHelper.database;
    await db.insert('assets', {
      'id': 'old',
      'name': 'Bem existente',
      'value': 123.45,
      'currency': 'BRL',
      'notes': '',
      'created_at': DateTime(2026).toIso8601String()
    });
    await db.execute('DROP TABLE investment_operations');
    await db.execute('DROP TABLE investments');
    await db.setVersion(23);
    await DBHelper.close();
    expect(
        await (await DBHelper.database).getVersion(), DBHelper.schemaVersion);
    expect((await DBHelper.getAssets()).single.value, 123.45);
    final legacy = await DBHelper.exportAll();
    legacy['version'] = 23;
    legacy.remove('investments');
    legacy.remove('investment_operations');
    await repository.create(asset(), op('a', 'opening', 10, 10000));
    final backup = await DBHelper.exportAll();
    await repository.record(op('b', 'buy', 2, 3000, day: 2));
    await DBHelper.importAll(backup);
    expect((await repository.load()).single.quantity, 10 * investmentScale);
    await DBHelper.importAll(legacy);
    expect(await repository.load(), isEmpty);
    expect((await DBHelper.getAssets()).single.value, 123.45);
    await (await DBHelper.database).delete('assets');
  });
  test('portfolio mutations never change bank ledger, assets or categories',
      () async {
    final before = await DBHelper.exportAll();
    await repository.create(asset(), op('a', 'buy', 10, 10000));
    await repository.record(op('b', 'sell', 2, 2500, day: 2));
    await repository.record(op('c', 'income', 0, 1000, day: 3));
    await repository.price('asset', 15000000, DateTime(2026, 10, 4), 'manual');
    final after = await DBHelper.exportAll();
    for (final key in before.keys
        .where((k) => !['investments', 'investment_operations'].contains(k))) {
      expect(after[key], before[key], reason: key);
    }
  });
  test('replay is idempotent; changed payload with same ID and oversell fail',
      () async {
    await repository.create(asset(), op('a', 'opening', 10, 10000));
    final sale = op('b', 'sell', 2, 2500, day: 2);
    await repository.record(sale);
    await repository.record(sale);
    expect((await repository.load()).single.quantity, 8 * investmentScale);
    await expectLater(repository.record(op('b', 'sell', 3, 2500, day: 2)),
        throwsFormatException);
    await expectLater(repository.record(op('c', 'sell', 9, 2500, day: 3)),
        throwsFormatException);
    expect((await repository.load()).single.operations.length, 2);
  });
  test('deleting acquisition backing a sale is blocked without partial writes',
      () async {
    await repository.create(asset(), op('a', 'opening', 10, 10000));
    await repository.record(op('b', 'sell', 2, 2500, day: 2));
    await expectLater(repository.removeOperation('a'), throwsFormatException);
    expect((await repository.load()).single.operations.length, 2);
    await repository.removeOperation('b');
    expect((await repository.load()).single.quantity, 10 * investmentScale);
  });
  test('invalid portfolio restore cannot erase live data', () async {
    await repository.create(asset(), op('a', 'opening', 10, 10000));
    final backup = await DBHelper.exportAll();
    backup['investment_operations'] = [op('b', 'sell', 20, 10000).toMap()];
    await expectLater(DBHelper.importAll(backup), throwsFormatException);
    expect((await repository.load()).single.quantity, 10 * investmentScale);
    final missing = await DBHelper.exportAll();
    missing.remove('investments');
    await expectLater(DBHelper.importAll(missing), throwsFormatException);
    final orphan = await DBHelper.exportAll();
    orphan['investments'] = [];
    await expectLater(DBHelper.importAll(orphan), throwsFormatException);
  });
  test('disk failure rolls back both investment and opening operation',
      () async {
    final db = await DBHelper.database;
    await db.execute(
        "CREATE TRIGGER fail_investment BEFORE INSERT ON investment_operations BEGIN SELECT RAISE(ABORT, 'synthetic disk failure'); END");
    try {
      await expectLater(
          repository.create(asset(), op('a', 'opening', 10, 10000)),
          throwsA(isA<DatabaseException>()));
      expect(await repository.load(), isEmpty);
    } finally {
      await db.execute('DROP TRIGGER fail_investment');
    }
  });
  test(
      'restart preserves portfolio and old network quote cannot replace newer price',
      () async {
    await repository.create(asset(), op('a', 'opening', 10, 10000));
    await repository.price('asset', 20000000, DateTime(2026, 10, 10), 'manual');
    await repository.price('asset', 10000000, DateTime(2026, 10, 9), 'brapi');
    await DBHelper.close();
    expect((await repository.load()).single.value, 20000);
  });
  Map<String, dynamic> quote() => {
        'results': [
          {
            'requestedSymbol': 'PETR4',
            'symbol': 'PETR4',
            'changed': false,
            'data': {
              'currency': 'BRL',
              'regularMarketPrice': 32.90,
              'regularMarketTime': '2026-10-01T17:00:00Z'
            }
          }
        ]
      };
  test(
      'quote request sends only ticker and auth header over HTTPS without redirects',
      () async {
    final api = InvestmentQuotes(
        clientFactory: () => MockClient((request) async {
              expect(request.url.scheme, 'https');
              expect(request.url.host, 'brapi.dev');
              expect(request.url.queryParameters, {'symbols': 'PETR4'});
              expect(
                  request.headers['Authorization'], 'Bearer synthetic-token');
              expect(request.followRedirects, false);
              expect(request.body, isEmpty);
              return http.Response(jsonEncode(quote()), 200);
            }));
    final result = await api.fetch('PETR4', token: 'synthetic-token');
    expect(result.priceMicros, 32900000);
  });
  for (final status in [401, 403, 429, 500, 302]) {
    test('quote HTTP $status never returns a false price', () async {
      final api = InvestmentQuotes(
          clientFactory: () => MockClient(
              (_) async => http.Response('private-provider-detail', status)));
      await expectLater(api.fetch('PETR4'), throwsA(isA<QuoteFailure>()));
    });
  }
  test(
      'wrong currency, renamed ticker, missing price and future date are rejected',
      () async {
    for (final mode in [
      'currency',
      'symbol',
      'changed',
      'price',
      'date',
      'size'
    ]) {
      final body = quote();
      final row = (body['results'] as List).single as Map;
      final data = row['data'] as Map;
      switch (mode) {
        case 'currency':
          data['currency'] = 'USD';
        case 'symbol':
          row['symbol'] = 'OTHER';
        case 'changed':
          row['changed'] = true;
        case 'price':
          data['regularMarketPrice'] = -10;
        case 'date':
          data['regularMarketTime'] = '2999-01-01T00:00:00Z';
      }
      final api = InvestmentQuotes(
          clientFactory: () => MockClient((_) async => http.Response(
              mode == 'size' ? 'x' * 140000 : jsonEncode(body), 200)));
      await expectLater(api.fetch('PETR4'), throwsA(isA<QuoteFailure>()),
          reason: mode);
    }
  });
  test('offline failure leaves persisted quote unchanged', () async {
    await repository.create(asset(), op('a', 'opening', 10, 10000));
    final api = InvestmentQuotes(
        clientFactory: () =>
            MockClient((_) async => throw const SocketException('offline')));
    await expectLater(api.fetch('PETR4'), throwsA(isA<QuoteFailure>()));
    expect((await repository.load()).single.value, 12000);
  });
}
