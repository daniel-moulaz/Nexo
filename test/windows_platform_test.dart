import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:excel/excel.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/platform_capabilities.dart';
import 'package:expensy/services/notification_service.dart';
import 'package:expensy/services/lended_notification_service.dart';
import 'package:expensy/services/loan_reminder_service.dart';
import 'package:expensy/services/credit_reminder_service.dart';
import 'package:expensy/services/daily_reminder_service.dart';
import 'package:expensy/services/budget_notification_service.dart';
import 'package:expensy/services/financial_reminders.dart';
import 'package:expensy/services/notification_inbox.dart';
import 'package:expensy/services/quick_add_service.dart';
import 'package:expensy/services/nexo_security.dart';
import 'package:expensy/services/file_output.dart';
import 'package:expensy/services/finance_export_service.dart';
import 'package:expensy/services/transaction_metadata_service.dart';
import 'package:expensy/services/financial_analysis.dart';
import 'package:expensy/services/card_invoice_service.dart';
import 'package:expensy/utils/finance_input.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('pt_BR'));
  late Directory directory;
  late AppProvider app;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('nexo-windows-test-');
    await DatabasePlatform.initialize(testDirectory: directory.path);
    app = AppProvider();
    app.settings.currency = 'BRL';
    app.settings.budgetAlertsEnabled = false;
    app.accounts = [
      Account(
          id: 'bank',
          name: 'Banco sintético',
          type: 'bank',
          currency: 'BRL',
          balance: 1000,
          colorValue: 0),
      Account(
          id: 'cash',
          name: 'Carteira',
          type: 'cash',
          currency: 'BRL',
          balance: 0,
          colorValue: 0),
      Account(
          id: 'card',
          name: 'Cartão',
          type: 'credit',
          currency: 'BRL',
          balance: 0,
          statementDay: 20,
          dueDay: 27,
          colorValue: 0),
    ];
    for (final account in app.accounts) {
      await DBHelper.insertAccount(account);
    }
  });
  tearDown(() async {
    await DBHelper.close();
    debugDefaultTargetPlatformOverride = null;
    app.dispose();
  });
  AppTransaction tx(String id,
          {double amount = 32.9,
          String type = 'expense',
          String account = 'bank'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: 'Teste local',
          accountId: account,
          categoryId: 'food_exp',
          date: DateTime.now(),
          currency: 'BRL');

  test('Windows opens schema 23 in configured user data and survives restart',
      () async {
    expect((await DBHelper.database).path, endsWith('expensy.db'));
    expect((await DBHelper.database).path, startsWith(directory.path));
    expect(await (await DBHelper.database).getVersion(), 23);
    await app.addTransaction(tx('one'));
    await DBHelper.close();
    expect((await DBHelper.getTransactions()).single.id, 'one');
    expect(
        (await DBHelper.getAccounts())
            .firstWhere((a) => a.id == 'bank')
            .balance,
        closeTo(967.1, .00001));
  });
  test('FFI existing database migrates 22 to 23 without balance changes',
      () async {
    final db = await DBHelper.database;
    await db.execute('DROP TABLE notification_suggestions');
    await db.setVersion(22);
    await DBHelper.close();
    expect(await (await DBHelper.database).getVersion(), 23);
    expect(
        (await DBHelper.getAccounts())
            .firstWhere((a) => a.id == 'bank')
            .balance,
        1000);
  });
  test('Windows CRUD, pending and transfers use the shared ledger', () async {
    await app.addTransaction(tx('income', type: 'income', amount: 100));
    await app.addTransaction(tx('paid', amount: 50));
    await app.addTransaction(tx('pending', amount: 200),
        metadata: const TransactionMetadata(
            transactionId: 'pending', status: 'pending'));
    expect(app.accountById('bank')!.balance, 1050);
    await app.updateTransaction(tx('paid', amount: 40),
        app.transactions.firstWhere((t) => t.id == 'paid'));
    expect(app.accountById('bank')!.balance, 1060);
    await app.addTransfer(fromId: 'bank', toId: 'cash', fromAmount: 80);
    expect(app.accountById('bank')!.balance, 980);
    expect(app.accountById('cash')!.balance, 80);
    final data = FinancialAnalysis(
        transactions: app.transactions,
        metadata: app.transactionMetadata,
        filter: FinancialAnalysis.month(DateTime.now(), DateTime.now()),
        amount: (t) => t.amount);
    expect(data.expense, 40);
    expect(data.pendingExpense, 200);
    await app.deleteTransaction('paid');
    expect(app.accountById('bank')!.balance, 1020);
  });
  test(
      'Windows card payment stays neutral and recurring occurrence is idempotent',
      () async {
    final now = DateTime.now();
    final cycleEnd = DateTime(now.year, now.month + (now.day > 20 ? 1 : 0), 20);
    await app.addTransaction(tx('card-purchase', amount: 100, account: 'card'));
    await app.addTransfer(
        fromId: 'bank',
        toId: 'card',
        fromAmount: 40,
        invoiceCycleEnd: cycleEnd);
    expect(app.accountById('bank')!.balance, 960);
    expect(app.accountById('card')!.balance, -60);
    expect(
        await CardInvoiceService.instance.paidForCycle('card', cycleEnd), 40);
    final recurring = RecurringPayment(
        id: 'internet',
        name: 'Internet sintética',
        accountId: 'bank',
        categoryId: 'food_exp',
        amount: 10,
        freqVal: 1,
        freqUnit: 'months',
        startDate: now,
        nextDate: now);
    await app.addRecurring(recurring);
    await Future.wait(
        [app.markRecurringPaid(recurring), app.markRecurringPaid(recurring)]);
    expect(app.accountById('bank')!.balance, 950);
    expect(await DBHelper.getRecurringHistory(recurring.id), hasLength(1));
    final budget = Budget(
        id: 'budget',
        categoryId: 'food_exp',
        amount: 200,
        period: 'monthly',
        createdAt: now);
    await app.addBudget(budget);
    expect(app.budgetSpent(budget), 110);
    final data = FinancialAnalysis(
        transactions: app.transactions,
        metadata: app.transactionMetadata,
        filter: FinancialAnalysis.month(now, now),
        amount: (t) => t.amount);
    expect(data.expense, 110);
    expect(app.totalBalanceAll, 890);
  });
  test('CSV, XLSX and JSON files round trip on the Windows filesystem',
      () async {
    await app.addTransaction(tx('export'));
    final from = DateTime(2000), to = DateTime(2100);
    final csv = await FinanceExportService.buildCsv(app, from: from, to: to);
    final csvPath = '${directory.path}/relatório.csv';
    await FileOutput.write(csvPath, Uint8List.fromList(utf8.encode(csv)));
    expect(await File(csvPath).readAsString(), contains('transaction_id'));
    final workbook =
        await FinanceExportService.buildWorkbook(app, from: from, to: to);
    final xlsxPath = '${directory.path}/relatório.xlsx';
    await FileOutput.write(xlsxPath, Uint8List.fromList(workbook.encode()!));
    expect(Excel.decodeBytes(await File(xlsxPath).readAsBytes()).tables.keys,
        contains('Transações'));
    final backup = await DBHelper.exportAll();
    final backupPath = '${directory.path}/backup.json';
    await FileOutput.write(
        backupPath, Uint8List.fromList(utf8.encode(jsonEncode(backup))));
    await app.addTransaction(tx('later'));
    await DBHelper.importAll(jsonDecode(await File(backupPath).readAsString()));
    expect((await DBHelper.getTransactions()).map((t) => t.id), ['export']);
    expect(
        (await DBHelper.getAccounts())
            .firstWhere((a) => a.id == 'bank')
            .balance,
        closeTo(967.1, .00001));
  });
  test('Replacing export is complete, and missing/locked files fail safely',
      () async {
    final file = File('${directory.path}/report.csv');
    await file.writeAsString('old');
    await FileOutput.write(file.path, Uint8List.fromList([65, 66]));
    expect(await file.readAsString(), 'AB');
    await expectLater(File('${directory.path}/missing.json').readAsString(),
        throwsA(isA<FileSystemException>()));
    await expectLater(
        FileOutput.write('${directory.path}/missing/report.csv', Uint8List(2)),
        throwsA(isA<FileSystemException>()));
    final handle = await file.open(mode: FileMode.append);
    await handle.lock(FileLock.blockingExclusive);
    try {
      await expectLater(FileOutput.write(file.path, Uint8List.fromList([90])),
          throwsA(isA<FileSystemException>()));
    } finally {
      await handle.unlock();
      await handle.close();
    }
    expect(await file.readAsString(), 'AB');
  });
  test('Android integrations are safe no-ops on Windows without native mocks',
      () async {
    expect(PlatformCapabilities.bankNotifications, false);
    await NotificationService().initialize();
    await NotificationService().cancelReminder('x');
    await BudgetNotificationService().initialize();
    await LendedNotificationService().initialize();
    await LendedNotificationService().cancelLendedReminder('x');
    await LoanReminderService().initialize();
    await LoanReminderService().cancelReminder('x');
    await CreditReminderService().initialize();
    await CreditReminderService().cancelReminder('x');
    await DailyReminderService().initialize();
    await DailyReminderService().cancelDailyReminder();
    await NotificationInbox.sync();
    await app.updateHomeWidgets();
    await FinancialReminders.instance.refresh(app);
    expect(await QuickAddService.instance.getInitialRoute(), null);
    expect(await QuickAddService.instance.routeStream.toList(), isEmpty);
  });
  test('Windows PIN locks after restart and focus loss; Hello cannot bypass it',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final security = NexoSecurity();
    await security.load();
    await security.setPin('918273');
    final restart = NexoSecurity();
    await restart.load();
    expect(restart.locked, true);
    expect(await restart.deviceAuth(), false);
    expect(await restart.verify('918274'), false);
    expect(await restart.verify('918273'), true);
    await restart.configure(timeout: 0);
    restart.background();
    restart.resume();
    expect(restart.locked, true);
    final raw =
        await const FlutterSecureStorage().read(key: NexoSecurity.storageKey);
    expect(raw, isNot(contains('918273')));
  });
  test('Brazilian decimal inputs and dates are unambiguous', () {
    expect(parseMoney('32,90'), 32.9);
    expect(parseMoney('32.90'), 32.9);
    expect(parseMoney('R\$ 1.234,56'), 1234.56);
    expect(parseMoney('1,234.56'), 1234.56);
    expect(parseMoney('32,901'), null);
    expect(parseMoney('32.90.00'), null);
    expect(ptDate(DateTime(2026, 9, 30, 15, 20)), '30/09/2026');
    expect(DateTime.parse(DateTime.now().toIso8601String()).isUtc, false);
  });
}
