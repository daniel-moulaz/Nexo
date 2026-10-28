import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/budget_insights.dart';
import 'package:nexo/services/spendable.dart';
import 'package:flutter_test/flutter_test.dart';

/// The persona of the plan: R$ 1.500 salary + R$ 250 grant, fixed bills,
/// delivery spending and an odd job that must not inflate the plan.
void main() {
  final now = DateTime(2026, 10, 21, 15);
  RecurringPayment rec(String id, double amount, int day,
          {String type = 'expense', DateTime? next}) =>
      RecurringPayment(
          id: id,
          name: id,
          accountId: 'mp',
          categoryId: 'c',
          amount: amount,
          paymentType: type,
          freqVal: 1,
          freqUnit: 'months',
          startDate: DateTime(2026, 1, day),
          nextDate: next ?? DateTime(2026, 10, day));
  AppTransaction tx(String id, double amount, int day,
          {String type = 'expense'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: id,
          accountId: 'mp',
          categoryId: 'c',
          date: DateTime(2026, 10, day, 12));

  test('fixed income minus bills, pending, goals and variable spending', () {
    final s = spendable(
        transactions: [
          // Salary already received (registered occurrence of the recurring).
          tx('recurring:salary:2026-10-05T00:00:00.000', 1500, 5,
              type: 'income'),
          tx('recurring:rent:2026-10-10T00:00:00.000', 233, 10),
          tx('delivery', 120, 18),
          tx('odd job', 100, 19, type: 'income'),
          tx('own pix', 500, 20, type: 'income'),
          tx('boleto', 50, 28),
        ],
        metadata: {
          'own pix': const TransactionMetadata(
              transactionId: 'own pix',
              excludeFromSpending: true,
              source: 'transfer:x'),
          'boleto': const TransactionMetadata(
              transactionId: 'boleto', status: 'pending'),
        },
        recurring: [
          rec('salary', 1500, 5, type: 'income', next: DateTime(2026, 11, 5)),
          rec('rent', 233, 10, next: DateTime(2026, 11, 10)),
          // Still to happen this month.
          rec('grant', 250, 25, type: 'income'),
          rec('spotify', 6.82, 28),
        ],
        goals: [
          SavingsGoal(
              id: 'g',
              name: 'Reserva',
              targetAmount: 1000,
              currentAmount: 400,
              currency: 'BRL',
              targetDate: DateTime(2027, 3, 31),
              colorValue: 0)
        ],
        toMain: (t) => t.amount,
        convert: (v, _) => v,
        currencyOf: (_) => 'BRL',
        now: now);
    expect(s.fixedIncome, 1750);
    expect(s.fixedBills, closeTo(239.82, 1e-9));
    expect(s.pendingBills, 50);
    expect(s.goals, closeTo(100, 1e-9)); // R$ 600 over Oct..Mar
    expect(s.variableSpent, 120);
    expect(s.free, closeTo(1750 - 239.82 - 50 - 100 - 120, 1e-9));
    expect(s.daysLeft, 11);
    expect(s.perDay, closeTo(s.free / 11, 1e-9));
  });

  test('without a recurring income there is no base to plan on', () {
    final s = spendable(
        transactions: [tx('odd job', 100, 19, type: 'income')],
        metadata: const {},
        recurring: const [],
        goals: const [],
        toMain: (t) => t.amount,
        convert: (v, _) => v,
        currencyOf: (_) => 'BRL',
        now: now);
    expect(s.hasBase, isFalse);
    expect(s.perDay, 0);
  });

  test('a budget created mid-month counts from that day, proportionally', () {
    final b = Budget(
        id: 'b',
        categoryId: 'bets',
        amount: 50,
        period: 'monthly',
        createdAt: DateTime(2026, 10, 20, 9));
    final w = budgetWindow(b, now);
    expect(w.partial, isTrue);
    expect(w.countsFrom, DateTime(2026, 10, 20));
    expect(w.limit, closeTo(50 * 12 / 31, .005));
    // Next month it is a full month.
    final next = budgetWindow(b, DateTime(2026, 11, 3));
    expect(next.partial, isFalse);
    expect(next.limit, 50);
    expect(next.countsFrom, DateTime(2026, 11));
    // Created on the first day: full from the start.
    final first = budgetWindow(
        Budget(
            id: 'f',
            categoryId: 'c',
            amount: 120,
            period: 'monthly',
            createdAt: DateTime(2026, 10, 1, 8)),
        now);
    expect(first.partial, isFalse);
    expect(first.limit, 120);
  });
}
