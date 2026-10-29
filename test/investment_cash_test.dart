import 'dart:io';
import 'dart:convert';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/transaction_metadata_service.dart';
import 'package:nexo/investments/investment_models.dart';
import 'package:nexo/investments/investment_repository.dart';
import 'package:nexo/services/finance_rules.dart';
import 'package:nexo/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late InvestmentRepository repo;
  final at = DateTime(2026, 10, 19);
  Investment asset() => Investment(
      id: 'asset',
      name: 'Ativo sintético',
      assetClass: 'Ações',
      ticker: 'PETR4',
      priceMicros: 10 * investmentScale,
      priceAt: at);
  InvestmentOperation op(String id, String kind, int units, int cents,
          {String? account = 'bank', int day = 0}) =>
      InvestmentOperation(
          id: id,
          investmentId: 'asset',
          kind: kind,
          quantity: units * investmentScale,
          cents: cents,
          date: at.add(Duration(days: day)),
          createdAt: at.add(Duration(days: day)),
          cashAccountId: account);
  Future<double> balance() async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == 'bank').balance;
  setUp(() async {
    await DBHelper.close();
    final directory =
        await Directory.systemTemp.createTemp('nexo-investment-cash-');
    await DatabasePlatform.initialize(testDirectory: directory.path);
    await DBHelper.insertAccount(Account(
        id: 'bank',
        name: 'Banco sintético',
        type: 'bank',
        currency: 'BRL',
        balance: 1000,
        colorValue: 0));
    repo = InvestmentRepository();
  });
  tearDown(() => DBHelper.close());

  test(
      '100 contribution reduces available 1000 to 900, preserves wealth and is not consumption',
      () async {
    await repo.create(asset(), op('buy', 'buy', 10, 10000));
    expect(await balance(), 900);
    expect((await repo.load()).single.value, 10000);
    expect(await balance() + (await repo.load()).single.value / 100, 1000);
    final data = await DBHelper.exportAll();
    final tx = (await DBHelper.getTransactions()).single;
    final metadata = TransactionMetadata.fromMap(
        (data['transaction_metadata'] as List).single);
    expect(FinanceRules.isNeutral(tx, metadata), true);
    expect(metadata.affectsBalance, true);
    await repo.record(op('buy', 'buy', 10, 10000));
    expect(await balance(), 900);
    expect((await DBHelper.getTransactions()).length, 1);
    await repo.price('asset', 12 * investmentScale, at, 'manual');
    expect(await balance(), 900);
  });

  test('sale credits cash once, proventos are income, reversal is atomic',
      () async {
    await repo.create(asset(), op('buy', 'buy', 10, 10000));
    await repo.record(op('sell', 'sell', 10, 12000, day: 1));
    await repo.record(op('income', 'income', 0, 500, day: 2));
    expect(await balance(), 1025);
    final data = await DBHelper.exportAll();
    final meta = (data['transaction_metadata'] as List)
        .map((m) => TransactionMetadata.fromMap(m))
        .toList();
    expect(
        meta
            .firstWhere((m) => m.transactionId == 'investment:sell')
            .excludeFromSpending,
        true);
    expect(
        meta
            .firstWhere((m) => m.transactionId == 'investment:income')
            .excludeFromSpending,
        false);
    await repo.removeOperation('income');
    await repo.removeOperation('income');
    expect(await balance(), 1020);
    await repo.removeOperation('sell');
    expect(await balance(), 900);
    await repo.removeOperation('buy');
    expect(await balance(), 1000);
    expect(await DBHelper.getTransactions(), isEmpty);
  });

  test('failed or excessive sale changes neither position nor cash', () async {
    await repo.create(asset(), op('buy', 'buy', 10, 10000));
    await expectLater(repo.record(op('sell', 'sell', 11, 12000, day: 1)),
        throwsFormatException);
    await expectLater(
        repo.record(op('sell', 'sell', 10, 12000, account: 'missing', day: 1)),
        throwsFormatException);
    expect(await balance(), 900);
    expect((await repo.load()).single.quantity, 10 * investmentScale);
    expect((await DBHelper.getTransactions()).length, 1);
  });

  test(
      'legacy positions never debit automatically; explicit link is idempotent',
      () async {
    await repo.create(
        asset(), op('opening', 'opening', 10, 10000, account: null));
    expect(await balance(), 1000);
    await repo.linkCash('opening', 'bank');
    await repo.linkCash('opening', 'bank');
    expect(await balance(), 900);
    expect((await repo.load()).single.quantity, 10 * investmentScale);
    expect((await DBHelper.getTransactions()).length, 1);
    await expectLater(DBHelper.deleteAccount('bank'), throwsFormatException);
  });

  test(
      'retire only closed position; history preserved and reopening restores visibility',
      () async {
    await repo.create(asset(), op('buy', 'buy', 10, 10000));
    await expectLater(repo.archive('asset'), throwsFormatException);
    await repo.record(op('sell', 'sell', 10, 12000, day: 1));
    await repo.archive('asset');
    expect((await repo.load()).single.investment.archived, true);
    expect((await repo.load()).single.operations.length, 2);
    expect(await balance(), 1020);
    await repo.removeOperation('sell');
    expect((await repo.load()).single.investment.archived, false);
    expect(await balance(), 900);
  });

  test(
      'backup restore does not replay cash and rejects broken links before replacing data',
      () async {
    await repo.create(asset(), op('buy', 'buy', 10, 10000));
    final backup = await DBHelper.exportAll();
    await repo.record(op('sell', 'sell', 10, 12000, day: 1));
    await DBHelper.importAll(backup);
    expect(await balance(), 900);
    expect((await repo.load()).single.quantity, 10 * investmentScale);
    await DBHelper.importAll(backup);
    expect(await balance(), 900);
    final bad = jsonDecode(jsonEncode(backup)) as Map<String, dynamic>;
    (bad['transactions'] as List).clear();
    await expectLater(DBHelper.importAll(bad), throwsFormatException);
    expect(await balance(), 900);
  });

  test(
      'v24 migration preserves cash and existing positions without linking them',
      () async {
    await repo.create(
        asset(), op('opening', 'opening', 10, 10000, account: null));
    final db = await DBHelper.database;
    await db.execute(
        'ALTER TABLE investment_operations DROP COLUMN cash_account_id');
    await db.execute('ALTER TABLE investments DROP COLUMN archived');
    await db.execute('ALTER TABLE categories DROP COLUMN envelope');
    await db.execute('DROP TABLE shared_settings');
    await db.setVersion(24);
    await DBHelper.close();
    expect(await (await DBHelper.database).getVersion(), 27);
    // v26 adds the kind of spending to categories.
    expect(
        (await (await DBHelper.database)
                .rawQuery('PRAGMA table_info(categories)'))
            .any((c) => c['name'] == 'envelope'),
        isTrue);
    // v27 adds the settings shared by the devices.
    expect(await DBHelper.getSharedSettings(), isEmpty);
    expect(await balance(), 1000);
    expect((await repo.load()).single.operations.single.cashAccountId, isNull);
    expect((await repo.load()).single.investment.archived, false);
  });

  test(
      'general ledger cannot edit or delete one side of an investment movement',
      () async {
    await repo.create(asset(), op('buy', 'buy', 10, 10000));
    final app = AppProvider();
    final tx = (await DBHelper.getTransactions()).single;
    await expectLater(app.deleteTransaction(tx.id), throwsFormatException);
    await expectLater(app.updateTransaction(tx, tx), throwsFormatException);
    expect(await balance(), 900);
    app.dispose();
  });

  test('linked cash account cannot become foreign currency or a credit card',
      () async {
    await repo.create(asset(), op('buy', 'buy', 10, 10000));
    final bank = (await DBHelper.getAccounts()).single;
    await expectLater(DBHelper.updateAccount(bank.copyWith(currency: 'USD')),
        throwsFormatException);
    final app = AppProvider();
    await expectLater(app.updateAccount(bank.copyWith(type: 'credit')),
        throwsFormatException);
    expect(await balance(), 900);
    expect((await DBHelper.getAccounts()).single.currency, 'BRL');
    expect((await DBHelper.getAccounts()).single.type, 'bank');
    app.dispose();
  });
}
