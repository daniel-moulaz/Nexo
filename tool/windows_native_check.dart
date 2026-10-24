// Native integration probe. Never package this entrypoint for distribution.
// Build with --target tool/windows_native_check.dart; run --test-profile.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:excel/excel.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../lib/database/database_platform.dart';
import '../lib/database/db_helper.dart';
import '../lib/models/models.dart';
import '../lib/providers/app_provider.dart';
import '../lib/services/desktop_profile.dart';
import '../lib/services/nexo_security.dart';
import '../lib/services/transaction_metadata_service.dart';
import '../lib/services/financial_analysis.dart';
import '../lib/services/card_invoice_service.dart';
import '../lib/services/finance_export_service.dart';
import '../lib/services/file_output.dart';
import '../lib/utils/finance_input.dart';

class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('Offline native test');
}

void check(bool ok, String label) {
  if (!ok) throw StateError(label);
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || !args.contains('--test-profile')) exit(64);
  HttpOverrides.global = _Offline();
  await DesktopProfile.initialize(args);
  final directory = File(await DatabasePlatform.path).parent;
  final resume = args.contains('--qa-resume');
  final report = <String, dynamic>{
    'phase': resume ? 'restart' : 'create',
    'offline': true
  };
  runApp(const MaterialApp(
      home: Scaffold(
          body: Center(
              child: Text('Nexo: validação nativa isolada em andamento')))));
  final app = AppProvider();
  final security = NexoSecurity();
  try {
    await initializeDateFormatting('pt_BR');
    const secure = FlutterSecureStorage();
    const markerKey = 'nexo_windows_native_probe_marker';
    if (resume) {
      check(await secure.read(key: markerKey) == 'phase-one-complete',
          'Native secure storage did not survive restart');
      await security.load();
      check(!security.storageError && security.enabled && security.locked,
          'PIN not locked on restart');
      check(!await security.verify('918274'), 'Wrong PIN accepted');
      check(await security.verify('918273'), 'Correct PIN rejected');
      for (var i = 0; i < 5; i++) {
        check(!await security.verify('918274'),
            'Wrong PIN accepted during failures');
      }
      check(security.retrySeconds > 0, 'Cooldown absent');
      check(!await security.verify('918273'), 'Cooldown bypassed');
      await app.load();
      check(
          app.settings.onboarded &&
              app.settings.userName == 'Teste Windows' &&
              app.settings.currency == 'BRL',
          'Restart settings');
      check(
          app.accountById('qa-bank')!.balance == 2050, 'Restart bank balance');
      check(app.accountById('qa-reserve')!.balance == 200, 'Restart reserve');
      check(app.accountById('qa-card')!.balance == 0, 'Restart card debt');
      check(app.transactions.length == 9, 'Restart duplicated or lost entries');
      await security.configure(enabled: false);
      final disabled = NexoSecurity();
      await disabled.load();
      check(
          !disabled.enabled && !disabled.locked, 'PIN removal did not persist');
      await secure.delete(key: markerKey);
      report.addAll({
        'nativeSecureStorage': 'passed',
        'pinRestartWrongCorrectCooldownDisable': 'passed',
        'entries': app.transactions.length
      });
    } else {
      check(
          (await DBHelper.getTransactions()).isEmpty &&
              (await DBHelper.getAccounts()).isEmpty,
          'Probe requires a fresh isolated database');
      app.settings.currency = 'BRL';
      app.settings.budgetAlertsEnabled = false;
      await app.completeOnboarding(name: 'Teste Windows', currency: 'BRL');
      for (final a in [
        Account(
            id: 'qa-bank',
            name: 'Banco Teste',
            type: 'bank',
            balance: 1000,
            currency: 'BRL',
            colorValue: 0),
        Account(
            id: 'qa-reserve',
            name: 'Conta Reserva',
            type: 'savings',
            balance: 0,
            currency: 'BRL',
            colorValue: 0),
        Account(
            id: 'qa-card',
            name: 'Cartão Teste',
            type: 'credit',
            balance: 0,
            currency: 'BRL',
            colorValue: 0,
            statementDay: 20,
            dueDay: 27),
      ]) {
        await app.addAccount(a);
      }
      final now = DateTime.now();
      AppTransaction tx(String id, String name, double value,
              {String type = 'expense',
              String account = 'qa-bank',
              String category = 'food_exp'}) =>
          AppTransaction(
              id: id,
              description: name,
              amount: value,
              type: type,
              accountId: account,
              categoryId: category,
              currency: 'BRL',
              date: now);
      await app.addTransaction(tx('qa-income', 'Salário Teste', 1500,
          type: 'income', category: 'salary'));
      await app.addTransaction(tx('qa-market', 'Mercado Teste', 100));
      await app.addTransaction(
          tx('qa-pending', 'Internet Teste', 80, category: 'bills'),
          metadata: const TransactionMetadata(
              transactionId: 'qa-pending', status: 'pending'));
      FinancialAnalysis analysis() => FinancialAnalysis(
          transactions: app.transactions,
          metadata: app.transactionMetadata,
          filter: FinancialAnalysis.month(now, now),
          amount: (t) => t.amount);
      check(app.accountById('qa-bank')!.balance == 2400,
          'Pending changed current balance');
      check(
          analysis().income == 1500 &&
              analysis().expense == 100 &&
              analysis().pendingExpense == 80,
          'Initial analytical totals');
      report['basic'] = {
        'bank': 2400,
        'income': 1500,
        'paidExpense': 100,
        'pending': 80
      };
      await app.addTransfer(
          fromId: 'qa-bank', toId: 'qa-reserve', fromAmount: 200);
      check(
          app.accountById('qa-bank')!.balance == 2200 &&
              app.accountById('qa-reserve')!.balance == 200 &&
              app.totalBalanceAll == 2400,
          'Transfer conservation');
      check(analysis().expense == 100, 'Transfer counted as consumption');
      report['transfer'] = {
        'bank': 2200,
        'reserve': 200,
        'total': 2400,
        'consumption': 100
      };
      await app.addTransaction(tx('qa-purchase', 'Compra Cartão', 120,
          account: 'qa-card', category: 'shopping'));
      check(
          app.accountById('qa-bank')!.balance == 2200 &&
              app.accountById('qa-card')!.balance == -120,
          'Card purchase cash/debt');
      final cycleEnd =
          DateTime(now.year, now.month + (now.day > 20 ? 1 : 0), 20);
      await app.addTransfer(
          fromId: 'qa-bank',
          toId: 'qa-card',
          fromAmount: 120,
          invoiceCycleEnd: cycleEnd);
      check(
          app.accountById('qa-bank')!.balance == 2080 &&
              app.accountById('qa-card')!.balance == 0,
          'Invoice payment balances');
      check(
          await CardInvoiceService.instance.paidForCycle('qa-card', cycleEnd) ==
                  120 &&
              analysis().expense == 220,
          'Invoice payment duplicated consumption');
      report['card'] = {
        'bankAfterPayment': 2080,
        'debt': 0,
        'consumption': 220,
        'total': app.totalBalanceAll
      };
      final budget = Budget(
          id: 'qa-budget',
          categoryId: 'food_exp',
          amount: 350,
          period: 'monthly',
          createdAt: now);
      await app.addBudget(budget);
      check(app.budgetSpent(budget) == 100, 'Budget consumption');
      report['budget'] = {
        'used': 100,
        'remaining': 250,
        'percent': 100 / 350 * 100
      };
      final recurring = RecurringPayment(
          id: 'qa-recurring',
          name: 'Mensalidade Teste',
          amount: 30,
          accountId: 'qa-bank',
          categoryId: 'bills',
          freqVal: 1,
          freqUnit: 'months',
          startDate: now,
          nextDate: now);
      await app.addRecurring(recurring);
      await Future.wait(
          [app.markRecurringPaid(recurring), app.markRecurringPaid(recurring)]);
      check(
          (await DBHelper.getRecurringHistory(recurring.id)).length == 1 &&
              app.accountById('qa-bank')!.balance == 2050,
          'Recurring duplicated');
      check((await DBHelper.getRecurring()).single.nextDate.isAfter(now),
          'Next occurrence');
      report['recurring'] = {'history': 1, 'bank': 2050};
      final backup = await DBHelper.exportAll();
      await FileOutput.write(
          '${directory.path}/backup.json', utf8.encode(jsonEncode(backup)));
      await app.updateTransaction(tx('qa-market', 'Mercado alterado', 777),
          app.transactions.firstWhere((t) => t.id == 'qa-market'));
      await DBHelper.importAll(jsonDecode(
          await File('${directory.path}/backup.json').readAsString()));
      await app.load();
      check(
          app.accountById('qa-bank')!.balance == 2050 &&
              app.transactions.firstWhere((t) => t.id == 'qa-market').amount ==
                  100,
          'Backup restore mismatch');
      final stable = jsonEncode(await DBHelper.exportAll());
      try {
        await DBHelper.importAll({'version': 23});
        throw StateError('Malformed backup accepted');
      } on FormatException {/* expected */}
      check(jsonEncode(await DBHelper.exportAll()) == stable,
          'Malformed restore modified data');
      final from = DateTime(now.year, now.month),
          to = DateTime(now.year, now.month + 1, 0);
      final csv = await FinanceExportService.buildCsv(app, from: from, to: to);
      await FileOutput.write('${directory.path}/export.csv', utf8.encode(csv));
      check(
          (await File('${directory.path}/export.csv').readAsString())
                  .contains('Salário Teste') &&
              csv.contains('transaction_id'),
          'CSV accents or ID missing');
      final workbook =
          await FinanceExportService.buildWorkbook(app, from: from, to: to);
      await FileOutput.write('${directory.path}/export.xlsx',
          Uint8List.fromList(workbook.encode()!));
      final decoded = Excel.decodeBytes(
          await File('${directory.path}/export.xlsx').readAsBytes());
      check(decoded['Transações'].rows.length == app.transactions.length + 1,
          'XLSX row count');
      for (final value in ['32,90', '32.90']) {
        check(parseMoney(value) == 32.9, 'Decimal $value');
      }
      for (final value in ['1.234,56', '1234,56']) {
        check(parseMoney(value) == 1234.56, 'Decimal $value');
      }
      report.addAll({
        'backupRestore': 'passed',
        'csvXlsx': 'passed',
        'entries': app.transactions.length,
        'schema': DBHelper.schemaVersion
      });
      await security.load();
      check(!security.storageError, 'Native secure storage read failed');
      await security.setPin('918273');
      await secure.write(key: markerKey, value: 'phase-one-complete');
      report['nativePinWrite'] = 'passed';
    }
    report['passed'] = true;
  } catch (error, stack) {
    report.addAll({
      'passed': false,
      'error': error.toString(),
      'stack': stack.toString()
    });
  } finally {
    await File('${directory.path}/native-${resume ? 'restart' : 'create'}.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report),
            flush: true);
    await DBHelper.close();
    app.dispose();
  }
  exit(report['passed'] == true ? 0 : 1);
}
