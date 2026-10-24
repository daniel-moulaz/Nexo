import 'package:expensy/models/models.dart';
import 'package:expensy/models/transaction_metadata.dart';
import 'package:expensy/services/week_summary.dart';
import 'package:flutter_test/flutter_test.dart';

AppTransaction _tx(String id, double amount, DateTime date,
        {String type = 'expense', String category = 'food'}) =>
    AppTransaction(
        id: id,
        type: type,
        amount: amount,
        description: id,
        accountId: 'a',
        categoryId: category,
        date: date);

void main() {
  // Wednesday 21/10/2026.
  final now = DateTime(2026, 10, 21, 15);

  test('the week starts on the configured day', () {
    expect(WeekSummary.startOf(now, 'monday'), DateTime(2026, 10, 19));
    expect(WeekSummary.startOf(now, 'sunday'), DateTime(2026, 10, 18));
    expect(WeekSummary.startOf(DateTime(2026, 10, 18), 'monday'),
        DateTime(2026, 10, 12));
  });

  test('this week against the same days of last week, by the app rules', () {
    final w = WeekSummary.build(transactions: [
      _tx('mon', 50, DateTime(2026, 10, 19)),
      _tx('wed', 150, DateTime(2026, 10, 21, 9), category: 'fun'),
      // Not spending: a transfer, a pending bill and income.
      _tx('move', 500, DateTime(2026, 10, 20)),
      _tx('bill', 90, DateTime(2026, 10, 20)),
      _tx('pay', 3000, DateTime(2026, 10, 20), type: 'income'),
      // Last week: Monday..Wednesday count, Thursday does not.
      _tx('lw', 100, DateTime(2026, 10, 14)),
      _tx('lthu', 999, DateTime(2026, 10, 15)),
    ], metadata: {
      'move':
          TransactionMetadata(transactionId: 'move', excludeFromSpending: true),
      'bill': TransactionMetadata(transactionId: 'bill', status: 'pending'),
    }, amount: (t) => t.amount, now: now);
    expect(w.spent, 200);
    expect(w.previousSpent, 100);
    expect(w.change, 100);
    expect(w.daysElapsed, 3);
    expect(w.quietDays, 1); // Tuesday
    expect(w.days, [50, 0, 150, 0, 0, 0, 0]);
    expect(w.topCategory!.key, 'fun');
    expect(w.biggest!.id, 'wed');
  });

  test('an empty week has no comparison and no highlights', () {
    final w = WeekSummary.build(
        transactions: const [],
        metadata: const {},
        amount: (t) => t.amount,
        now: now,
        weekStart: 'sunday');
    expect(w.spent, 0);
    expect(w.change, isNull);
    expect(w.quietDays, 4);
    expect(w.biggest, isNull);
    expect(w.topCategory, isNull);
  });
}
