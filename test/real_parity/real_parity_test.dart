// Local check on a COPY of the person's ledger. Nothing leaves the PC and
// no amount is printed; the copy and outputs stay in build/ (ignored by git)
// and should be deleted afterwards.
//
//   mkdir -p build/real_parity/copy
//   cp "%LOCALAPPDATA%/Nexo/<banco>.db" build/real_parity/copy/nexo.db
//   flutter test test/real_parity/real_parity_test.dart   # app numbers
//   node tool/real_parity/check.mjs                       # server mirror
//   (fresh copy) flutter test test/real_parity/write_path_test.dart
//   rm -rf build/real_parity
//
// The app's own rules compute the numbers; the server mirror input is
// written next to them for check.mjs.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/services/billing_cycle.dart';
import 'package:nexo/services/envelopes.dart';
import 'package:nexo/services/financial_analysis.dart';
import 'package:nexo/services/transaction_metadata_service.dart';
import 'package:nexo/sync/ledger_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Skipped unless a copy was placed there by hand (never in CI).
  final copy = File('build/real_parity/copy/nexo.db');
  test('real ledger copy', skip: !copy.existsSync(), () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final dir = Directory('build/real_parity/copy').absolute.path;
    await DatabasePlatform.initialize(testDirectory: dir);
    final db = await DBHelper.database; // the COPY migrates to schema 27
    final version =
        (await db.rawQuery('PRAGMA user_version')).single.values.first;

    final rows = <String, List<Map<String, Object?>>>{};
    for (final e in ledgerTables.entries) {
      rows[e.key] = [
        for (final r in await db.query(e.key)) LedgerCapture.value(e.key, r)
      ];
    }
    final accounts = await db.query('accounts');
    final ledger = {
      'mainCurrency': 'BRL',
      'accounts': rows['accounts'],
      'balances': {
        for (final a in accounts) a['id']: ((a['balance'] as num) * 1e6).round()
      },
      'categories': rows['categories'],
      'transactions': rows['transactions'],
      'metadata': rows['transaction_metadata'],
      'recurring': rows['recurring_payments'],
      'recurringHistory': rows['recurring_history'],
      'investments': rows['investments'],
      'investmentOperations': rows['investment_operations'],
      'budgets': rows['budgets'],
      'goals': rows['savings_goals'],
      'contributions': rows['savings_contributions'],
      'loans': rows['loans'],
      'loanPayments': rows['loan_payments'],
      'lended': rows['lended_money'],
      'lendedPeople': rows['lended_people'],
      'assets': rows['assets'],
      'wishlist': rows['wishlist'],
      'invoicePayments': rows['card_invoice_payments'],
      'importRules': rows['import_rules'],
      'sharedSettings': rows['shared_settings'],
      'devices': const [],
    };

    final app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.accounts = await DBHelper.getAccounts();
    app.categories = await DBHelper.getCategories();
    app.transactions = await DBHelper.getTransactions();
    app.transactionMetadata = await TransactionMetadataService.instance
        .getForMany(app.transactions.map((t) => t.id));
    app.budgets = await DBHelper.getBudgets();
    app.savingsContributions = await DBHelper.getAllSavingsContributions();

    final now = DateTime.now();
    String d(DateTime x) => x.toIso8601String().substring(0, 10);
    int c(double v) => (v * 100).round();
    final brl = app.transactions.where((t) =>
        (t.currency.isEmpty
            ? app.accountById(t.accountId)?.currency ?? 'BRL'
            : t.currency) ==
        'BRL');

    final months = <Map<String, Object?>>[];
    for (var i = 0; i < 3; i++) {
      final first = DateTime(now.year, now.month - i);
      final f = FinancialAnalysis.month(first, now);
      final a = FinancialAnalysis(
          transactions: brl,
          metadata: app.transactionMetadata,
          filter: f,
          amount: (t) => t.amount);
      months.add({
        'from': d(f.from),
        'to': d(f.to),
        'income': c(a.income),
        'expense': c(a.expense),
        'refunds': c(a.refunds),
        'pendingExpense': c(a.pendingExpense),
        'transfers': c(a.transfers),
        'result': c(a.result),
        'categories': {for (final e in a.categories.entries) e.key: c(e.value)},
      });
    }

    final budgets = [
      for (final b in app.budgets)
        {
          'id': b.id,
          'limit': c(app.budgetLimit(b)),
          'spent': c(app.budgetSpent(b)),
        }
    ];

    final start = DateTime(now.year, now.month).toIso8601String();
    final end = DateTime(now.year, now.month + 1).toIso8601String();
    final invested = (await db.rawQuery(
            "SELECT COALESCE(SUM(cents), 0) AS c FROM investment_operations "
            "WHERE kind = 'buy' AND date >= ? AND date < ?",
            [start, end]))
        .first['c'] as num;
    final report = envelopeReport(
      categories: app.categories,
      transactions: brl.toList(),
      metadata: app.transactionMetadata,
      contributions: app.savingsContributions,
      investedCents: invested.toInt(),
      shares: defaultEnvelopeShares,
      referenceIncome: 1800,
      toMain: (t) => t.amount,
      now: now,
    );
    final envelopes = {
      'month': d(now).substring(0, 7),
      'lines': {
        for (final l in report.lines)
          l.def.id: {'planned': c(l.planned), 'spent': c(l.spent)}
      },
      'unassignedSpent': c(report.unassignedSpent),
    };

    // Invoices like the "Pagar fatura" rule: purchases of the cycle (neutral
    // ones out, adjustments in) minus payments keyed by the closing date.
    final invoices = <Map<String, Object?>>[];
    for (final card in app.accounts.where((a) => a.type == 'credit')) {
      var cycle = BillingCycle.forDate(now, card.statementDay, card.dueDay);
      for (var k = 0; k < 3; k++) {
        final key = d(cycle.end);
        final purchases = (await db.rawQuery(
                "SELECT COALESCE(SUM(CASE WHEN t.type = 'income' THEN -t.amount ELSE t.amount END), 0) AS total "
                "FROM transactions t LEFT JOIN transaction_metadata m ON m.transaction_id = t.id "
                "WHERE t.account_id = ? AND t.date >= ? AND t.date < ? "
                "AND (COALESCE(m.exclude_from_spending, 0) = 0 OR m.source = 'opening_balance')",
                [
              card.id,
              cycle.start.toIso8601String(),
              cycle.until.toIso8601String()
            ]))
            .first['total'] as num;
        final paid = (await db.rawQuery(
                'SELECT COALESCE(SUM(amount), 0) AS total FROM card_invoice_payments WHERE card_id = ? AND cycle_end = ?',
                [card.id, key]))
            .first['total'] as num;
        invoices.add({
          'card': card.id,
          'closing': key,
          'total': c(purchases.toDouble()),
          'paid': c(paid.toDouble()),
        });
        cycle = BillingCycle.forDate(
            cycle.start.subtract(const Duration(days: 1)),
            card.statementDay,
            card.dueDay);
      }
    }

    File('build/real_parity/mirror.json').writeAsStringSync(
        jsonEncode({'today': d(now), 'ledger': ledger, 'schema': version}));
    File('build/real_parity/expected.json').writeAsStringSync(jsonEncode({
      'months': months,
      'budgets': budgets,
      'envelopes': envelopes,
      'invoices': invoices,
    }));
    // ignore: avoid_print
    print('schema $version; tables ${rows.length}; '
        'transactions ${rows['transactions']!.length}; budgets ${budgets.length}; '
        'cards ${invoices.length ~/ 3}');
  });
}
