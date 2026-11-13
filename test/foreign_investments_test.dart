// Dollar stocks: two currencies, an exchange between accounts, quotes that
// fail, and net worth that counts each real once. Fictitious figures only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/investments/foreign_quotes.dart';
import 'package:nexo/investments/investment_models.dart';
import 'package:nexo/investments/investment_quotes.dart';
import 'package:nexo/investments/investment_repository.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/net_worth_history.dart';
import 'package:nexo/sync/supabase_auth.dart';
import 'package:nexo/sync/sync_config.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final at = DateTime(2026, 11, 3);

Investment nvda({int price = 120, int fx = 5500000}) => Investment(
    id: 'nvda',
    name: 'Ação americana sintética',
    assetClass: 'Ações',
    ticker: 'NVDA',
    institution: 'Corretora EUA',
    priceMicros: price * investmentScale,
    priceAt: at,
    currency: 'USD',
    fxMicros: fx);

InvestmentOperation usd(String id, String kind,
        {int units = 0,
        required int cents,
        int? brl,
        int tax = 0,
        int day = 0,
        String? account}) =>
    InvestmentOperation(
        id: id,
        investmentId: 'nvda',
        kind: kind,
        quantity: units * investmentScale,
        cents: cents,
        brlCents: brl,
        taxCents: tax,
        date: at.add(Duration(days: day)),
        createdAt: at.add(Duration(days: day)),
        cashAccountId: account);

class _Auth extends SupabaseAuth {
  _Auth() : super(SyncConfig(Uri.parse('https://example.test'), 'pk'));
  @override
  Future<String?> accessToken() async => 'session';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a position in two currencies', () {
    // 10 shares at US$ 100 with the dollar at R$ 5,00; today US$ 120 and
    // R$ 5,50.
    final buy = usd('b', 'buy', units: 10, cents: 100000, brl: 500000);

    test('cost in dollars and in reais, value at today\'s rate', () {
      final p = InvestmentPosition(nvda(), [buy]);
      expect(p.nativeCost, 100000);
      expect(p.cost, 500000);
      expect(p.nativeValue, 120000);
      expect(p.value, 660000);
      expect(p.averageCost, 10000); // US$ 100,00 per share
      expect(p.averageFx, 5000000);
    });

    test('price effect and exchange effect add up to the change', () {
      final p = InvestmentPosition(nvda(), [buy]);
      expect(p.priceEffect, 110000); // US$ 200 × 5,50
      expect(p.fxEffect, 50000); // US$ 1.000 × (5,50 − 5,00)
      expect(p.priceEffect + p.fxEffect, p.unrealized);
    });

    test('a sale takes out the cost in reais of the day it was bought', () {
      final p = InvestmentPosition(nvda(), [
        buy,
        usd('s', 'sell', units: 5, cents: 65000, brl: 338000, day: 3),
      ]);
      expect(p.cost, 250000);
      expect(p.nativeCost, 50000);
      expect(p.realized, 88000);
      expect(p.nativeRealized, 15000);
      expect(p.sales, 338000);
    });

    test('a dividend keeps net, withheld and the reais of the day', () {
      final p = InvestmentPosition(nvda(), [
        buy,
        usd('d', 'income', cents: 700, brl: 3640, tax: 300, day: 10),
      ]);
      expect(p.nativeIncome, 700);
      expect(p.nativeTax, 300);
      expect(p.income, 3640);
    });

    test(
        'a dollar operation without reais is refused, a real one with them too',
        () {
      expect(
          () => InvestmentPosition(
              nvda(), [usd('x', 'buy', units: 1, cents: 100)]),
          throwsFormatException);
      expect(
          () => InvestmentPosition(
              Investment(
                  id: 'nvda',
                  name: 'BR',
                  assetClass: 'Ações',
                  priceMicros: 1,
                  priceAt: at),
              [usd('x', 'buy', units: 1, cents: 100, brl: 500)]),
          throwsFormatException);
    });

    test('withheld tax only on a dividend', () {
      expect(
          () => usd('x', 'buy', units: 1, cents: 1, brl: 5, tax: 1).validate(),
          throwsFormatException);
    });

    test('an asset in reais is unchanged', () {
      final p = InvestmentPosition(
          Investment(
              id: 'a',
              name: 'Ação BR',
              assetClass: 'Ações',
              priceMicros: 12 * investmentScale,
              priceAt: at),
          [
            InvestmentOperation(
                id: 'b',
                investmentId: 'a',
                kind: 'buy',
                quantity: 10 * investmentScale,
                cents: 10000,
                date: at,
                createdAt: at)
          ]);
      expect([p.cost, p.value, p.priceEffect, p.fxEffect],
          [10000, 12000, 2000, 0]);
    });
  });

  group('tickers', () {
    test('the fractional market of the B3 is the base asset', () {
      expect(normalizeTicker('bbas3f'), 'BBAS3');
      expect(normalizeTicker('BPAC11F'), 'BPAC11');
      expect(normalizeTicker('PETR4'), 'PETR4');
    });

    test('a US ticker stays as it is, even one letter or with a dot', () {
      expect(normalizeTicker('nvda', currency: 'USD'), 'NVDA');
      for (final t in ['F', 'BRK.B', 'NVDA']) {
        expect(
            () => Investment(
                    id: 'u',
                    name: t,
                    assetClass: 'Ações',
                    ticker: t,
                    priceMicros: 1,
                    priceAt: at,
                    currency: 'USD',
                    fxMicros: 5000000)
                .validate(),
            returnsNormally);
      }
    });
  });

  group('net worth', () {
    test('a dollar stock counts once, in reais, at cost and at market', () {
      final inputs = NetWorthInputs(
          accounts: const [],
          transactions: const [],
          metadata: const {},
          positions: [
            InvestmentPosition(nvda(),
                [usd('b', 'buy', units: 10, cents: 100000, brl: 500000)])
          ],
          convert: (v, c) => v);
      expect(inputs.costAt(at), 5000);
      expect(inputs.marketValue, 6600);
    });
  });

  group('the portfolio database', () {
    late InvestmentRepository repo;
    Future<double> balance(String id) async =>
        (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;
    setUp(() async {
      await DBHelper.close();
      final dir = await Directory.systemTemp.createTemp('nexo-foreign-');
      await DatabasePlatform.initialize(testDirectory: dir.path);
      for (final (id, currency) in [('real', 'BRL'), ('dolar', 'USD')]) {
        await DBHelper.insertAccount(Account(
            id: id,
            name: id,
            type: 'bank',
            currency: currency,
            balance: 1000,
            colorValue: 0));
      }
      repo = InvestmentRepository();
    });
    tearDown(() => DBHelper.close());

    test('a dollar buy moves the dollar account, in dollars', () async {
      await repo.create(
          nvda(),
          usd('b', 'buy',
              units: 1, cents: 12000, brl: 66000, account: 'dolar'));
      expect(await balance('dolar'), 880);
      expect(await balance('real'), 1000);
      final p = (await repo.load()).single;
      expect(p.cost, 66000);
      final tx = (await DBHelper.getTransactions())
          .singleWhere((t) => t.id == InvestmentRepository.cashId('b'));
      expect(tx.currency, 'USD');
    });

    test('a dollar buy never takes reais from a real account', () async {
      await expectLater(
          repo.create(
              nvda(),
              usd('b', 'buy',
                  units: 1, cents: 12000, brl: 66000, account: 'real')),
          throwsFormatException);
      expect(await balance('real'), 1000);
      expect(await repo.load(), isEmpty);
    });

    test('today\'s rate reaches every dollar asset, a real one stays',
        () async {
      await repo.create(nvda(fx: 5000000),
          usd('b', 'opening', units: 1, cents: 12000, brl: 60000));
      await repo.refreshFx('USD', 5400000);
      expect((await repo.load()).single.investment.fxMicros, 5400000);
      await repo.refreshFx('BRL', 2000000);
      expect((await repo.load()).single.investment.fxMicros, 5400000);
    });

    test('a quote of the US keeps the rate it came with', () async {
      await repo.create(
          nvda(), usd('b', 'opening', units: 1, cents: 12000, brl: 60000));
      await repo.price('nvda', 130 * investmentScale,
          at.add(const Duration(days: 1)), 'mercado',
          fxMicros: 5600000);
      final p = (await repo.load()).single;
      expect(p.investment.priceSource, 'mercado');
      expect(p.value, 72800);
    });

    test('a new database already has the dollar columns', () async {
      final db = await DBHelper.database;
      expect(await db.query('investments'), isEmpty);
      final rows =
          await db.rawQuery('PRAGMA table_info(investment_operations)');
      expect(
          rows.map((r) => r['name']), containsAll(['brl_cents', 'tax_cents']));
    });
  });

  test('schema 28 only adds columns, and old rows read as reais', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('''CREATE TABLE investments (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, asset_class TEXT NOT NULL,
      ticker TEXT NOT NULL, institution TEXT NOT NULL,
      price_micros INTEGER NOT NULL, price_at TEXT NOT NULL,
      price_source TEXT NOT NULL, archived INTEGER NOT NULL DEFAULT 0)''');
    await db.execute('''CREATE TABLE investment_operations (
      id TEXT PRIMARY KEY, investment_id TEXT NOT NULL, kind TEXT NOT NULL,
      quantity INTEGER NOT NULL, cents INTEGER NOT NULL, date TEXT NOT NULL,
      created_at TEXT NOT NULL, cash_account_id TEXT)''');
    await db.insert('investments', {
      'id': 'old',
      'name': 'Antiga',
      'asset_class': 'Ações',
      'ticker': 'PETR4',
      'institution': 'Corretora',
      'price_micros': 30 * investmentScale,
      'price_at': at.toUtc().toIso8601String(),
      'price_source': 'manual'
    });
    await db.insert('investment_operations', {
      'id': 'op',
      'investment_id': 'old',
      'kind': 'buy',
      'quantity': 2 * investmentScale,
      'cents': 5000,
      'date': at.toUtc().toIso8601String(),
      'created_at': at.toUtc().toIso8601String()
    });
    await InvestmentRepository.addCurrency(db);
    await InvestmentRepository.addCurrency(db); // twice is harmless
    final p = InvestmentRepository.decode(await db.query('investments'),
            await db.query('investment_operations'))
        .single;
    expect(p.investment.currency, 'BRL');
    expect(p.investment.fxMicros, fxScale);
    expect(p.operations.single.brlCents, isNull);
    expect([p.cost, p.value], [5000, 6000]);
    await db.close();
  });

  group('US quotes', () {
    SupabaseForeignQuotes source(MockClient client) => SupabaseForeignQuotes(
        SyncConfig(Uri.parse('https://example.test'), 'pk'), _Auth(),
        clientFactory: () => client);

    test('only tickers go out, and a dollar price comes back with its date',
        () async {
      late Map body;
      final got = await source(MockClient((r) async {
        body = jsonDecode(r.body) as Map;
        expect(r.url.path, '/functions/v1/market-quotes');
        expect(r.headers['Authorization'], 'Bearer session');
        return http.Response(
            jsonEncode({
              'quotes': [
                {
                  'symbol': 'NVDA',
                  'price': 166.19,
                  'currency': 'USD',
                  'time': '2026-11-12T21:00:00.000Z'
                }
              ]
            }),
            200);
      })).fetch({'NVDA', 'XXXX'});
      expect(body.keys, ['symbols']);
      expect(got.keys, ['NVDA']);
      expect(got['NVDA']!.priceMicros, 166190000);
    });

    test('a server without a key says so and changes nothing', () async {
      await expectLater(
          source(MockClient((_) async => http.Response('{}', 503)))
              .fetch({'NVDA'}),
          throwsA(isA<QuoteFailure>()
              .having((e) => e.message, 'message', contains('sem chave'))));
    });

    test('a network failure keeps the last price', () async {
      await expectLater(
          source(MockClient((_) async => throw const SocketException('off')))
              .fetch({'NVDA'}),
          throwsA(isA<QuoteFailure>()
              .having((e) => e.message, 'message', contains('preservado'))));
    });

    test('a wrong currency, a bad price or a future date is dropped', () {
      final now = DateTime.utc(2026, 11, 13);
      final got = SupabaseForeignQuotes.parse({
        'quotes': [
          {'symbol': 'A', 'price': 10, 'currency': 'BRL', 'time': '2026-11-12'},
          {'symbol': 'B', 'price': -1, 'currency': 'USD', 'time': '2026-11-12'},
          {'symbol': 'C', 'price': 10, 'currency': 'USD', 'time': '2026-12-01'},
          {'symbol': 'D', 'price': 10, 'currency': 'USD', 'time': '2026-11-12'},
          {'symbol': 'Z', 'price': 10, 'currency': 'USD', 'time': '2026-11-12'},
        ]
      }, {
        'A',
        'B',
        'C',
        'D'
      }, now);
      expect(got.keys, ['D']);
    });

    test(
        'history: the server closes, in order, at the same date here and there',
        () async {
      late Map body;
      final got = await source(MockClient((r) async {
        body = jsonDecode(r.body) as Map;
        return http.Response(
            jsonEncode({
              'symbol': 'NVDA',
              'currency': 'USD',
              'points': [
                {'day': '2026-11-12', 'close_micros': 141000000},
                {'day': '2026-11-11', 'close_micros': 138000000},
                {'day': '2026-11-10', 'close_micros': 0},
              ],
              'backfilled': false
            }),
            200);
      })).history('NVDA');
      expect(body, {'history': 'NVDA'});
      expect(got.points.map((p) => p.price), [138, 141]);
      expect(got.points.first.date, DateTime.utc(2026, 11, 11, 12));
    });

    test('history from an older server says it is not published yet', () async {
      await expectLater(
          source(MockClient((_) async => http.Response('{}', 503)))
              .history('NVDA'),
          throwsA(isA<QuoteFailure>().having(
              (e) => e.message, 'message', contains('Histórico dos EUA'))));
      expect(
          () => SupabaseForeignQuotes.parseHistory(
              {'symbol': 'AAPL', 'points': []}, 'NVDA', DateTime.now()),
          throwsFormatException,
          reason: 'another ticker is never drawn');
    });
  });
}
