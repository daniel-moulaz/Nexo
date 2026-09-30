import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/services/financial_analysis.dart';
import 'package:expensy/services/transaction_metadata_service.dart';
import 'package:expensy/services/notification_preferences.dart';
import 'package:expensy/services/entry_defaults.dart';

void main() {
  AppTransaction tx(String id,
          {String type = 'expense',
          double amount = 100,
          String account = 'bank',
          DateTime? date,
          String category = 'food'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: id,
          accountId: account,
          categoryId: category,
          date: date ?? DateTime(2026, 9, 15),
          currency: 'BRL');
  TransactionMetadata meta(String id,
          {bool neutral = false,
          String status = 'paid',
          String source = 'manual',
          String expenseClass = 'normal',
          String sub = ''}) =>
      TransactionMetadata(
          transactionId: id,
          excludeFromSpending: neutral,
          status: status,
          source: source,
          expenseClass: expenseClass,
          subcategory: sub);
  FinancialAnalysis analyze(
          List<AppTransaction> txs, Map<String, TransactionMetadata> metas,
          {AnalysisFilter? filter}) =>
      FinancialAnalysis(
          transactions: txs,
          metadata: metas,
          filter: filter ??
              AnalysisFilter(
                  from: DateTime(2026, 9), to: DateTime(2026, 9, 30)),
          amount: (t) => t.accountId == 'usd' ? t.amount * 5 : t.amount);

  test(
      'Consumption excludes transfers, reserves, invoice payments and pending entries',
      () {
    final rows = [
      tx('salary', type: 'income', amount: 1000),
      tx('purchase', account: 'card'),
      tx('transfer-out'),
      tx('transfer-in', type: 'income'),
      tx('reserve'),
      tx('invoice'),
      tx('pending'),
      tx('refund', type: 'income', amount: 30)
    ];
    final metas = {
      'transfer-out':
          meta('transfer-out', neutral: true, source: 'transfer:pair'),
      'transfer-in':
          meta('transfer-in', neutral: true, source: 'transfer:pair'),
      'reserve': meta('reserve', neutral: true),
      'invoice': meta('invoice', neutral: true),
      'pending':
          meta('pending', status: 'pending', expenseClass: 'extraordinary'),
      'refund': meta('refund', source: 'notification_refund')
    };
    final data = analyze(rows, metas);
    expect(data.expense, 100);
    expect(data.income, 1000);
    expect(data.refunds, 30);
    expect(data.result, 930);
    expect(data.transfers, 100);
    expect(data.pendingExpense, 100);
    expect(data.normal, 100);
    expect(data.extraordinary, 0);
    expect(data.categories, {'food': 100});
    expect(rows.length, 8); // Input and ledger are untouched.
  });
  test('Category IDs stay distinct, conversion and recurrence use metadata',
      () {
    final data = analyze([
      tx('a', account: 'usd'),
      tx('b', category: 'other'),
      tx('c')
    ], {
      'a': meta('a', source: 'recurring', sub: 'Delivery'),
      'b': meta('b', expenseClass: 'extraordinary'),
    });
    expect(data.expense, 700);
    expect(data.categories, {'food': 600, 'other': 100});
    expect(data.recurring, 500);
    expect(data.variable, 200);
    expect(data.normal, 600);
    expect(data.subcategories['Delivery'], 500);
  });
  test('Filters compose including subcategory and inclusive final microsecond',
      () {
    final end = DateTime(2026, 9, 30, 23, 59, 59, 999, 999);
    final data = analyze([
      tx('yes', date: end),
      tx('no', date: DateTime(2026, 10)),
      tx('other-account', account: 'card'),
      tx('income', type: 'income')
    ], {
      for (final id in ['yes', 'no', 'other-account', 'income'])
        id: meta(id, sub: 'Delivery')
    },
        filter: AnalysisFilter(
            from: DateTime(2026, 9),
            to: DateTime(2026, 9, 30),
            accountId: 'bank',
            categoryId: 'food',
            subcategory: 'Delivery',
            type: 'expense'));
    expect(data.realized.map((t) => t.id), ['yes']);
  });
  test('Comparison uses same days, handles February and zero base', () {
    final current =
        FinancialAnalysis.month(DateTime(2026, 3), DateTime(2026, 3, 31));
    final previous = FinancialAnalysis.previousMonth(current, partial: true);
    expect(previous.to, DateTime(2026, 2, 28));
    final partial =
        FinancialAnalysis.month(DateTime(2026, 9), DateTime(2026, 9, 12));
    expect(FinancialAnalysis.previousMonth(partial, partial: true).to,
        DateTime(2026, 8, 12));
    expect(analyze([], {}).changeFrom(analyze([], {})), isNull);
    expect(
        analyze([tx('a', amount: 80)], {}).changeFrom(analyze([tx('b')], {})),
        -20);
  });
  test('Remembered accounts are explicit, scoped, removable and revalidated',
      () async {
    SharedPreferences.setMockInitialValues({});
    final scope =
        NotificationPreferences.scope('bank.app', 'credit', 'expense');
    final card = Account(
        id: 'card',
        name: 'Cartão',
        type: 'credit',
        balance: 0,
        currency: 'BRL',
        colorValue: 0);
    await NotificationPreferences.remember(scope, card.id);
    final rules = await NotificationPreferences.load();
    expect(
        NotificationPreferences.suggest(rules, scope, [card],
            medium: 'credit', type: 'expense'),
        'card');
    expect(
        NotificationPreferences.suggest(rules, scope, [],
            medium: 'credit', type: 'expense'),
        isNull);
    expect(
        NotificationPreferences.suggest(rules, scope, [card],
            medium: 'bank', type: 'expense'),
        isNull);
    expect(
        NotificationPreferences.suggest(rules, scope, [card],
            medium: 'credit', type: 'transfer'),
        isNull);
    await NotificationPreferences.clear();
    expect(await NotificationPreferences.load(), isEmpty);
  });
  test(
      'Recent account suggestion ignores imports, pending and neutral operations',
      () {
    final bank = Account(
        id: 'bank',
        name: 'Banco',
        type: 'bank',
        balance: 0,
        currency: 'BRL',
        colorValue: 0);
    final card = Account(
        id: 'card',
        name: 'Cartão',
        type: 'credit',
        balance: 0,
        currency: 'BRL',
        colorValue: 0);
    expect(
        EntryDefaults.recentAccount([
          bank,
          card
        ], [
          tx('manual', date: DateTime(2026, 9, 1)),
          tx('import', account: 'card'),
          tx('pending', account: 'card'),
          tx('neutral', account: 'card')
        ], {
          'import': meta('import', source: 'import'),
          'pending': meta('pending', status: 'pending'),
          'neutral': meta('neutral', neutral: true)
        }, 'expense')
            ?.id,
        'bank');
  });
}
