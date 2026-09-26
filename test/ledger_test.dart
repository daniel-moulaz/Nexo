import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/transaction_metadata_service.dart';
import 'package:expensy/services/card_invoice_service.dart';
import 'package:expensy/services/finance_export_service.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:expensy/services/import_rules_service.dart';

void main() {
  late AppProvider app;
  test('Private widgets never persist balances or budget values', () async {
    final payloads=<String,dynamic>{};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('home_widget'),(call) async {
      if(call.method=='saveWidgetData') payloads[call.arguments['id']]=jsonDecode(call.arguments['data']);
      return true;
    });
    app.budgets=[Budget(id:'b',categoryId:'bills',amount:1500,period:'monthly',createdAt:DateTime.now())];
    app.settings.hideBalance=true;
    await app.updateHomeWidgets();
    expect((payloads['accounts_widget_data'] as List).first['balance'],'••••');
    final budget=(payloads['budget_widget_data'] as List).single;
    expect(budget['hidden'],true);expect(budget['amount'],0);expect(budget['spent'],0);expect(budget['progress'],0);
  });
  test('CSV export preserves text identifiers, metadata and original decimals',
      () async {
    final t = AppTransaction(
        id: 'csv',
        type: 'expense',
        amount: 1234.56,
        description: '00123',
        accountId: 'bank',
        categoryId: 'bills',
        date: DateTime(2026, 9, 20),
        note: '=SUM(A1)');
    await app.addTransaction(t,
        metadata: const TransactionMetadata(
            transactionId: 'csv',
            subcategory: 'Transporte',
            status: 'pending'));
    final csv = await FinanceExportService.buildCsv(app,
        from: DateTime(2026, 9, 20), to: DateTime(2026, 9, 20));
    expect(csv, contains('"00123"'));
    expect(csv, contains('1234.56'));
    expect(csv, contains('Transporte'));
    expect(csv, contains('Pendente'));
    expect(csv, contains("'=SUM(A1)"));
    expect(csv.startsWith('\uFEFF'), isTrue);
  });
  test('v21 upgrade preserves ledger and rules survive backup restore',
      () async {
    final db = await DBHelper.database;
    await db.execute('DROP TABLE import_rules');
    await db.setVersion(21);
    await DBHelper.close();
    final upgraded = await DBHelper.database;
    expect(await upgraded.getVersion(), 22);
    expect((await upgraded.query('accounts')).length, 3);
    await upgraded.insert('categories', {
      'id': 'rulecat',
      'name': 'Transporte',
      'type': 'expense',
      'color_value': 0
    });
    const rule = ImportRule(
        id: 'rule',
        pattern: 'uber',
        type: 'expense',
        categoryId: 'rulecat',
        subcategory: 'Aplicativo');
    await ImportRulesService.save(rule);
    final backup = await DBHelper.exportAll();
    await DBHelper.importAll(backup);
    expect((await ImportRulesService.load()).single.subcategory, 'Aplicativo');
    await ImportRulesService.delete('rule');
    expect(await ImportRulesService.load(), isEmpty);
    await expectLater(
        ImportRulesService.save(const ImportRule(
            id: 'bad', pattern: '', type: 'expense', categoryId: 'rulecat')),
        throwsArgumentError);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir = await Directory.systemTemp.createTemp('nexo-ledger-test-');
    await databaseFactory.setDatabasesPath(dir.path);
  });
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('home_widget'),(call) async => true);
    await DBHelper.importAll({'version': DBHelper.schemaVersion});
    app = AppProvider();
    app.settings.budgetAlertsEnabled = false;
    for (final a in [
      Account(
          id: 'bank',
          name: 'Banco',
          type: 'bank',
          balance: 1000,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'cash',
          name: 'Carteira',
          type: 'wallet',
          balance: 0,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'card',
          name: 'Cartão',
          type: 'credit',
          balance: 0,
          currency: 'BRL',
          colorValue: 0,
          statementDay: 20,
          dueDay: 27),
    ]) {
      await DBHelper.insertAccount(a);
    }
    app.accounts = await DBHelper.getAccounts();
  });
  AppTransaction tx(String id,
          {String account = 'bank',
          String type = 'expense',
          double amount = 100,
          DateTime? date}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: 'Compra',
          accountId: account,
          categoryId: 'bills',
          date: date ?? DateTime.now());

  test('Fresh schema and lossless backup/restore include auxiliary data',
      () async {
    final t = tx('backup');
    await app.addTransaction(t,
        metadata: TransactionMetadata(
            transactionId: t.id,
            status: 'pending',
            subcategory: 'Energia',
            dueDate: DateTime(2026, 10, 3),
            expenseClass: 'extraordinary',
            source: 'import',
            affectsBalance: false));
    await CardInvoiceService.instance.recordPayment(
        id: 'p', cardId: 'card', cycleEnd: DateTime(2026, 9, 20), amount: 10);
    final backup = await DBHelper.exportAll();
    await DBHelper.importAll(backup);
    final m = await TransactionMetadataService.instance.getFor(t.id);
    expect(m.subcategory, 'Energia');
    expect(m.isPending, isTrue);
    expect(m.affectsBalance, isFalse);
    expect(
        await CardInvoiceService.instance
            .paidForCycle('card', DateTime(2026, 9, 20)),
        10);
    await app.deleteTransaction(t.id);
    expect(
        (await DBHelper.database).query('transaction_metadata',
            where: 'transaction_id = ?', whereArgs: [t.id]),
        completion(isEmpty));
  });
  test('Pending, settlement, editing and deletion change balance exactly once',
      () async {
    final t = tx('pending');
    await app.addTransaction(t,
        metadata: TransactionMetadata(transactionId: t.id, status: 'pending'));
    expect(app.accountById('bank')!.balance, 1000);
    await app.updateTransaction(t, t,
        metadata: TransactionMetadata(transactionId: t.id));
    expect(app.accountById('bank')!.balance, 900);
    await app.updateTransaction(t, t,
        metadata: TransactionMetadata(transactionId: t.id));
    expect(app.accountById('bank')!.balance, 900);
    await app.deleteTransaction(t.id);
    expect(app.accountById('bank')!.balance, 1000);
  });
  test('Transfer preserves wealth and does not spend budget', () async {
    await app.addTransfer(fromId: 'bank', toId: 'cash', fromAmount: 200);
    expect(app.accountById('bank')!.balance, 800);
    expect(app.accountById('cash')!.balance, 200);
    expect(app.totalBalanceAll, 1000);
    expect(app.transactionMetadata.values.every((m) => m.excludeFromSpending),
        isTrue);
    await expectLater(
        app.addTransfer(fromId: 'bank', toId: 'bank', fromAmount: 100),
        throwsArgumentError);
  });
  test('Card purchase and partial payment do not create a second expense',
      () async {
    await app.addTransaction(
        tx('purchase', account: 'card', date: DateTime(2026, 9, 20, 18)));
    expect(app.accountById('bank')!.balance, 1000);
    expect(app.totalBalanceAll, 900);
    await app.addTransfer(
        fromId: 'bank',
        toId: 'card',
        fromAmount: 40,
        invoiceCycleEnd: DateTime(2026, 9, 20));
    expect(app.accountById('bank')!.balance, 960);
    expect(app.accountById('card')!.balance, -60);
    expect(app.totalBalanceAll, 900);
    expect(
        await CardInvoiceService.instance
            .paidForCycle('card', DateTime(2026, 9, 20)),
        40);
    await expectLater(
        app.addTransfer(
            fromId: 'bank',
            toId: 'card',
            fromAmount: 100,
            invoiceCycleEnd: DateTime(2026, 9, 20)),
        throwsStateError);
    expect(app.accountById('bank')!.balance, 960);
  });
  test('3 of 12 generates ten installments, future bank expenses stay pending',
      () async {
    await app.addTransaction(tx('series', date: DateTime(2026, 1, 31)),
        metadata: const TransactionMetadata(
            transactionId: 'series',
            installmentCurrent: 3,
            installmentTotal: 12));
    expect(app.transactions, hasLength(10));
    expect(app.accountById('bank')!.balance, 900);
    expect(app.transactions.where((t) => t.date == DateTime(2026, 2, 28)),
        hasLength(1));
    expect(app.transactions.where((t) => t.date == DateTime(2026, 3, 31)),
        hasLength(1));
    await expectLater(
        app.addTransaction(tx('series')), throwsA(isA<DatabaseException>()));
    expect(app.accountById('bank')!.balance, 900);
  });
  test('Imported history keeps current balance when edited or removed',
      () async {
    final t = tx('history');
    await app.addTransaction(t,
        metadata: const TransactionMetadata(
            transactionId: 'history', affectsBalance: false, source: 'import'));
    await app.updateTransaction(t.copyWith(amount: 200), t);
    await app.deleteTransaction(t.id);
    expect(app.accountById('bank')!.balance, 1000);
  });
  RecurringPayment recurringFixture({String type = 'subscription'}) => RecurringPayment(
      id: 'r', name: 'Internet', accountId: 'bank', categoryId: 'bills',
      amount: 100, freqVal: 1, freqUnit: 'months',
      startDate: DateTime(2026, 1, 31), nextDate: DateTime(2026, 1, 31),
      endDate: DateTime(2026, 3, 31), recurringType: type);

  void expectProgress(RecurringPayment r, {required int paid,
      required int skipped, required int remaining, required double progress}) {
    expect(r.totalPayments, 3);
    expect(r.paidPayments, paid);
    expect(r.skippedPayments, skipped);
    expect(r.completedOccurrences, paid + skipped);
    expect(r.remainingPayments, remaining);
    expect(r.remainingAmount, remaining * 100);
    expect(r.progress, closeTo(progress, .000001));
  }

  test('Normal recurring payment counts as paid and consumes one occurrence', () async {
    final r = recurringFixture();
    await DBHelper.insertRecurring(r);
    await Future.wait([app.markRecurringPaid(r), app.markRecurringPaid(r)]);
    expectProgress(app.recurring.single, paid: 1, skipped: 0, remaining: 2, progress: 1/3);
    expect(app.accountById('bank')!.balance, 900);
    expect(app.transactions, hasLength(1));
    expect((await DBHelper.getRecurringHistory('r')).single.action, 'paid');
    expect(app.recurring.single.nextDate, DateTime(2026, 2, 28));
  });

  test('Normal skip consumes an occurrence without payment, including after edit and restore', () async {
    final r = recurringFixture();
    await DBHelper.insertRecurring(r);
    await Future.wait([app.skipNextRecurring(r), app.skipNextRecurring(r)]);
    expectProgress(app.recurring.single, paid: 0, skipped: 1, remaining: 2, progress: 1/3);
    expect(app.transactions, isEmpty);
    expect(app.accountById('bank')!.balance, 1000);
    expect((await DBHelper.getRecurringHistory('r')).single.action, 'skipped');
    await DBHelper.updateRecurring(app.recurring.single);
    await DBHelper.importAll(await DBHelper.exportAll());
    final restored = (await DBHelper.getRecurring()).single;
    expectProgress(restored, paid: 0, skipped: 1, remaining: 2, progress: 1/3);
    expect(restored.nextDate, DateTime(2026, 2, 28));
    await app.markRecurringPaid(restored);
    expectProgress(app.recurring.single, paid: 1, skipped: 1, remaining: 1, progress: 2/3);
    await app.skipNextRecurring(app.recurring.single);
    expectProgress(app.recurring.single, paid: 1, skipped: 2, remaining: 0, progress: 1);
    expect(app.recurring.single.canComplete, false);
    await app.markRecurringPaid(app.recurring.single);
    expect(app.transactions, hasLength(1));
    expect(app.accountById('bank')!.balance, 900);
  });

  test('Installment payment advances progress; skip is rejected without any writes', () async {
    final r = RecurringPayment(
        id: 'r',
        name: 'Internet',
        accountId: 'bank',
        categoryId: 'bills',
        amount: 100,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 1, 31),
        nextDate: DateTime(2026, 1, 31),
        endDate: DateTime(2026, 3, 31),
        recurringType: 'installment');
    await DBHelper.insertRecurring(r);
    await Future.wait([app.markRecurringPaid(r), app.markRecurringPaid(r)]);
    expect(app.transactions, hasLength(1));
    expect(app.accountById('bank')!.balance, 900);
    expect(app.recurring.single.recurringType, 'installment');
    expect(app.recurring.single.nextDate, DateTime(2026, 2, 28));
    expectProgress(app.recurring.single, paid: 1, skipped: 0, remaining: 2, progress: 1/3);
    final before = await DBHelper.exportAll();
    await expectLater(app.skipNextRecurring(app.recurring.single), throwsStateError);
    expect(await DBHelper.exportAll(), before);
    expectProgress(app.recurring.single, paid: 1, skipped: 0, remaining: 2, progress: 1/3);
    expect(app.transactions, hasLength(1));
    expect(app.recurring.single.nextDate, DateTime(2026, 2, 28));
    await app.markRecurringPaid(app.recurring.single);
    expectProgress(app.recurring.single, paid: 2, skipped: 0, remaining: 1, progress: 2/3);
    await app.markRecurringPaid(app.recurring.single);
    await app.markRecurringPaid(app.recurring.single);
    expectProgress(app.recurring.single, paid: 3, skipped: 0, remaining: 0, progress: 1);
    expect(app.transactions, hasLength(3));
    expect(app.accountById('bank')!.balance, 700);
    expect(await DBHelper.getRecurringHistoryCount(), 3);
  });

  test('Legacy skipped installment stays owed and explicit recovery preserves schedule and ordinal', () async {
    final r = recurringFixture(type: 'installment');
    final db = await DBHelper.database;
    // Exact old encoding: all three occurrences consumed, none actually paid.
    await db.insert('recurring_payments', {...r.toMap(), 'paid_payments': 3,
      'next_date': DateTime(2026, 4, 30).toIso8601String()});
    for (final date in [DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31)]) {
      await DBHelper.insertRecurringHistory(RecurringHistoryEntry(
          id: 'recurring:r:${date.toIso8601String()}', recurringId: 'r',
          action: 'skipped', date: date, amount: 100, currency: 'BRL'));
    }
    await DBHelper.importAll(await DBHelper.exportAll());
    final legacy = (await DBHelper.getRecurring()).single;
    expectProgress(legacy, paid: 0, skipped: 3, remaining: 3, progress: 0);
    expect(legacy.canComplete, true);
    expect(legacy.canSkip, false);
    await expectLater(app.skipNextRecurring(legacy), throwsStateError);
    for (var ordinal = 1; ordinal <= 3; ordinal++) {
      final current = (await DBHelper.getRecurring()).single;
      await Future.wait([app.markRecurringPaid(current), app.markRecurringPaid(current)]);
      final result = app.recurring.single;
      expectProgress(result, paid: ordinal, skipped: 3-ordinal, remaining: 3-ordinal, progress: ordinal/3);
      expect(result.nextDate, DateTime(2026, 4, 30));
      expect(app.transactions, hasLength(ordinal));
      expect(app.accountById('bank')!.balance, 1000 - ordinal * 100);
      final id = 'recurring:r:${current.nextActionDate.toIso8601String()}';
      final metadata = await db.query('transaction_metadata', where: 'transaction_id = ?', whereArgs: [id]);
      expect(metadata.single['installment_current'], ordinal);
      expect(metadata.single['installment_total'], 3);
      expect((await db.query('recurring_payments')).single['paid_payments'], 3);
    }
    expect(app.recurring.single.canComplete, false);
    expect(await DBHelper.getRecurringHistoryCount(), 3);
    expect((await DBHelper.getRecurringHistory('r')).every((e) => e.action == 'paid'), true);
  });
  test('Monthly budget excludes future periods and neutral transfers',
      () async {
    final now = DateTime.now();
    await app.addTransaction(tx('this', amount: 80));
    await app.addTransaction(
        tx('next', date: DateTime(now.year, now.month + 1), amount: 500));
    final budget = Budget(
        id: 'b',
        categoryId: 'bills',
        amount: 100,
        createdAt: now,
        period: 'monthly');
    expect(app.budgetSpent(budget), 80);
    expect(app.budgetProgress(budget), .8);
    expect(app.budgetRemaining(budget), 20);
    expect(app.budgetExceeded(budget), isFalse);
  });
  test('Deleting either transfer side removes both; undo restores both',
      () async {
    await app.addTransfer(fromId: 'bank', toId: 'cash', fromAmount: 200);
    final undo = await app.deleteTransactionWithUndo(app.transactions.first.id);
    expect(app.transactions, isEmpty);
    expect(app.accountById('bank')!.balance, 1000);
    expect(app.accountById('cash')!.balance, 0);
    undo();
    // VoidCallback intentionally returns void: wait for the actual restored state.
    for (var i = 0; i < 100 && app.transactions.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(app.transactions, hasLength(2));
    expect(app.totalBalanceAll, 1000);
  });
  test(
      'Version 20 upgrade preserves legacy metadata and creates missing tables',
      () async {
    final db = await DBHelper.database;
    await db.execute('DROP TABLE transaction_metadata');
    await db.execute(
        "CREATE TABLE transaction_metadata(transaction_id TEXT PRIMARY KEY, subcategory TEXT, status TEXT, due_date TEXT)");
    await db.insert('transaction_metadata', {
      'transaction_id': 'legacy',
      'subcategory': 'Farmácia',
      'status': 'pending'
    });
    await db.execute('DROP TABLE card_invoice_payments');
    await db.setVersion(20);
    await DBHelper.close();
    final upgraded = await DBHelper.database;
    expect(await upgraded.getVersion(), DBHelper.schemaVersion);
    final m = await TransactionMetadataService.instance.getFor('legacy');
    expect(m.subcategory, 'Farmácia');
    expect(m.isPending, isTrue);
    expect(await upgraded.query('card_invoice_payments'), isEmpty);
  });
  test('Excel round trip has all six sheets and financial metadata', () async {
    await app.addTransaction(tx('excel'),
        metadata: const TransactionMetadata(
            transactionId: 'excel',
            subcategory: 'Energia',
            status: 'pending',
            expenseClass: 'extraordinary'));
    final workbook = await FinanceExportService.buildWorkbook(app,
        from: DateTime(2000), to: DateTime(2100));
    final decoded = Excel.decodeBytes(workbook.encode()!);
    expect(
        decoded.tables.keys,
        containsAll([
          'Resumo',
          'Transações',
          'Contas',
          'Cartões',
          'Orçamentos',
          'Objetivos'
        ]));
    expect(decoded['Transações'].rows[1][7]!.value.toString(), 'Energia');
    expect(decoded['Transações'].rows[1][8]!.value.toString(), 'Pendente');
    expect(decoded['Transações'].rows[1][3]!.value,
        anyOf(isA<DoubleCellValue>(), isA<IntCellValue>()));
  });
  test('Goal deposit and withdrawal move reserves without creating expenses',
      () async {
    await app.addSavingsGoal(SavingsGoal(
        id: 'g',
        name: 'Reserva',
        targetAmount: 1000,
        currency: 'BRL',
        colorValue: 0));
    await app.contributeToGoal(goalId: 'g', fromAccountId: 'bank', amount: 200);
    expect(app.accountById('bank')!.balance, 800);
    expect(app.savingsGoals.single.currentAmount, 200);
    expect(app.transactions, isEmpty);
    await app.withdrawFromGoal(goalId: 'g', toAccountId: 'bank', amount: 50);
    expect(app.accountById('bank')!.balance, 850);
    expect(app.savingsGoals.single.currentAmount, 150);
    await expectLater(
        app.withdrawFromGoal(goalId: 'g', toAccountId: 'bank', amount: 200),
        throwsStateError);
    expect(app.accountById('bank')!.balance, 850);
  });
  test('Opening card debt is payable but does not count as new spending',
      () async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month + 1, 0);
    await app.addAccount(Account(
        id: 'opening',
        name: 'Cartão anterior',
        type: 'credit',
        balance: -300,
        currency: 'BRL',
        colorValue: 0));
    expect(app.reportTransactions, isEmpty);
    await app.addTransfer(
        fromId: 'bank', toId: 'opening', fromAmount: 100, invoiceCycleEnd: end);
    expect(app.accountById('opening')!.balance, -200);
    expect(app.accountById('bank')!.balance, 900);
    expect(app.reportTransactions, isEmpty);
  });
}
