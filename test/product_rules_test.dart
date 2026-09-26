import 'package:flutter_test/flutter_test.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/services/cash_forecast.dart';
import 'package:expensy/services/import_rules_service.dart';
import 'package:expensy/services/transaction_filter.dart';
import 'package:expensy/services/transaction_metadata_service.dart';
import 'package:expensy/services/finance_export_service.dart';

void main() {
  final bank = Account(
      id: 'bank',
      name: 'Banco',
      type: 'bank',
      balance: 1000,
      currency: 'BRL',
      colorValue: 0);
  final card = Account(
      id: 'card',
      name: 'Cartão',
      type: 'credit',
      balance: -300,
      currency: 'BRL',
      colorValue: 0,
      statementDay: 20,
      dueDay: 27);
  AppTransaction tx(String id,
          {String account = 'bank',
          String type = 'expense',
          double amount = 100,
          DateTime? date}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: 'Internet',
          accountId: account,
          categoryId: 'bills',
          date: date ?? DateTime(2026, 9, 20));
  CashForecast forecast(
          {List<AppTransaction> transactions = const [],
          List<RecurringPayment> recurring = const [],
          Map<String, TransactionMetadata> metadata = const {},
          List<Map<String, dynamic>> payments = const [],
          DateTime? until,
          List<Account>? accounts}) =>
      CashForecast.calculate(
          now: DateTime(2026, 9, 20),
          until: until ?? DateTime(2026, 9, 30),
          accounts: accounts ?? [bank, card],
          transactions: transactions,
          recurring: recurring,
          metadata: metadata,
          invoicePayments: payments,
          convert: (v, c) => v);
  test(
      'Forecast includes overdue and horizon income, excludes settled and historical',
      () {
    final result = forecast(transactions: [
      tx('paid'),
      tx('pending'),
      tx('income', type: 'income', amount: 400),
      tx('later'),
      tx('history')
    ], metadata: {
      'pending': TransactionMetadata(
          transactionId: 'pending',
          status: 'pending',
          dueDate: DateTime(2026, 9, 10)),
      'income': TransactionMetadata(
          transactionId: 'income',
          status: 'pending',
          dueDate: DateTime(2026, 9, 30, 23)),
      'later': TransactionMetadata(
          transactionId: 'later',
          status: 'pending',
          dueDate: DateTime(2026, 10, 1)),
      'history': const TransactionMetadata(
          transactionId: 'history', status: 'pending', affectsBalance: false)
    });
    expect(result.current, 1000);
    expect(result.projected, 1300);
    expect(bank.balance, 1000);
  });
  test('Card partial payment refund and closing boundary count cash once', () {
    final result = forecast(transactions: [
      tx('purchase', account: 'card', amount: 300),
      tx('refund', account: 'card', type: 'income', amount: 50),
      tx('future', account: 'card', amount: 500, date: DateTime(2026, 9, 21)),
      tx('debit', amount: 100),
      tx('credit', account: 'card', type: 'income', amount: 100)
    ], metadata: {
      'debit': const TransactionMetadata(
          transactionId: 'debit',
          excludeFromSpending: true,
          source: 'transfer:debit'),
      'credit': const TransactionMetadata(
          transactionId: 'credit',
          excludeFromSpending: true,
          source: 'transfer:debit')
    }, payments: [
      {'card_id': 'card', 'cycle_end': '2026-09-20', 'amount': 100}
    ]);
    expect(result.projected, 850);
    expect(result.events.where((e) => e.kind == 'invoice').single.amount, -150);
  });
  test(
      'Recurring expands without mutation, stops at end and avoids recorded occurrence',
      () {
    final r = RecurringPayment(
        id: 'r',
        name: 'Conta',
        accountId: 'bank',
        categoryId: 'bills',
        amount: 10,
        freqVal: 1,
        freqUnit: 'weeks',
        startDate: DateTime(2026, 9, 20),
        nextDate: DateTime(2026, 9, 20),
        endDate: DateTime(2026, 9, 27));
    expect(forecast(recurring: [r]).projected, 980);
    expect(r.nextDate, DateTime(2026, 9, 20));
    expect(
        forecast(recurring: [
          r
        ], transactions: [
          tx('recurring:r:2026-09-20T00:00:00.000', amount: 10)
        ]).projected,
        990);
  });
  test('Recurring card purchase hits cash at invoice due', () {
    final r = RecurringPayment(
        id: 'r',
        name: 'Streaming',
        accountId: 'card',
        categoryId: 'bills',
        amount: 30,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 9, 21),
        nextDate: DateTime(2026, 9, 21));
    expect(forecast(recurring: [r]).projected, 1000);
    expect(
        forecast(recurring: [r], until: DateTime(2026, 10, 27)).projected, 970);
  });
  test('Unconfigured card warns and excluded cash stays excluded', () {
    final u = Account(
        id: 'u',
        name: 'Sem data',
        type: 'credit',
        balance: -100,
        currency: 'BRL',
        colorValue: 0);
    final reserve = Account(
        id: 'r',
        name: 'Reserva',
        type: 'savings',
        balance: 900,
        currency: 'BRL',
        colorValue: 0,
        excludeFromTotal: true);
    final result = forecast(accounts: [bank, u, reserve]);
    expect(result.current, 1000);
    expect(result.warnings.any((w) => w.contains('vencimento')), isTrue);
  });
  test(
      'Rules match case insensitively, specific first, respecting type and valid category',
      () {
    final cats = [
      AppCategory(id: 'bills', name: 'Contas', type: 'expense', colorValue: 0)
    ];
    final rules = [
      const ImportRule(
          id: '1', pattern: 'uber', type: 'expense', categoryId: 'bills'),
      const ImportRule(
          id: '2',
          pattern: 'UBER TRIP',
          type: 'expense',
          categoryId: 'bills',
          subcategory: 'Aplicativo'),
      const ImportRule(
          id: '3',
          pattern: 'UBER TRIP BR',
          type: 'expense',
          categoryId: 'removed')
    ];
    expect(ImportRulesService.match(rules, 'uber trip br', 'expense', cats)?.id,
        '2');
    expect(ImportRulesService.match(rules, 'uber trip br', 'income', cats),
        isNull);
  });
  test('Reconciliation only suggests same account type amount within 3 days',
      () {
    final list = [
      tx('yes'),
      tx('wrongaccount', account: 'card'),
      tx('wrongtype', type: 'income'),
      tx('wrongvalue', amount: 100.01),
      tx('old', date: DateTime(2026, 9, 16))
    ];
    expect(
        ImportRulesService.candidates(list,
                accountId: 'bank',
                date: DateTime(2026, 9, 20),
                amount: 100,
                type: 'expense')
            .map((t) => t.id),
        ['yes']);
    expect(list.length, 5);
  });
  test(
      'Filters compose inclusive day amount status installments and neutral type',
      () {
    final f = TransactionFilter()
      ..from = DateTime(2026, 9, 20)
      ..to = DateTime(2026, 9, 20)
      ..minimum = 100
      ..maximum = 100
      ..status = 'pending'
      ..installmentsOnly = true;
    const m = TransactionMetadata(
        transactionId: 't', status: 'pending', installmentTotal: 12);
    expect(f.matches(tx('t', date: DateTime(2026, 9, 20, 23, 59)), m), isTrue);
    expect(f.matches(tx('t', amount: 101), m), isFalse);
    const neutral =
        TransactionMetadata(transactionId: 't', excludeFromSpending: true);
    expect(TransactionFilter.matchesType(tx('t'), neutral, 'expense'), isFalse);
    expect(TransactionFilter.matchesType(tx('t'), neutral, 'neutral'), isTrue);
  });
  test('CSV preserves delimiters and quotes and neutralizes formulas', () {
    expect(FinanceExportService.csvCell('a,"b"\nc'), '"a,""b""\nc"');
    expect(FinanceExportService.csvCell(' =HYPERLINK("x")').startsWith('"\''),
        isTrue);
    expect(FinanceExportService.csvCell('-12.50', numeric: true), '"-12.50"');
  });
}
