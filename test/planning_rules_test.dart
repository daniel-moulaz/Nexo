import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/planning_rules.dart';

void main() {
  const rule = BudgetRule(base: 50, percent: 50, incomeCategoryId: 'ganhos');

  test('base plus a share of the profit', () {
    final r = rule.apply(earned: 300, spent: 100);
    expect(r.profit, closeTo(200, .001));
    expect(r.limit, closeTo(150, .001));
  });

  test('a loss never lowers the base', () {
    expect(rule.apply(earned: 10, spent: 100).limit, 50);
    expect(rule.apply(earned: 0, spent: 0).limit, 50);
  });

  test('rules survive the trip through the settings', () {
    final back = BudgetRule.fromJson(rule.toJson())!;
    expect(
        [back.base, back.percent, back.incomeCategoryId], [50, 50, 'ganhos']);
    expect(BudgetRule.fromJson(null), isNull);
    expect(BudgetRule.fromJson({'base': 1}), isNull);
    expect(EmergencyPlan.fromJson(const {}), isNull);
  });

  final now = DateTime(2026, 11, 6);
  RecurringPayment charge(double amount, int every, String unit,
          {String type = 'expense', DateTime? end}) =>
      RecurringPayment(
          id: '$amount$unit',
          name: 'x',
          accountId: 'a',
          categoryId: 'c',
          amount: amount,
          paymentType: type,
          freqVal: every,
          freqUnit: unit,
          startDate: DateTime(2026, 1, 1),
          nextDate: DateTime(2026, 12, 1),
          endDate: end);

  test('fixed costs in an average month, whatever the frequency', () {
    expect(monthlyFixedCosts([charge(100, 1, 'months')], now), 100);
    expect(monthlyFixedCosts([charge(1200, 1, 'years')], now), 100);
    expect(monthlyFixedCosts([charge(300, 3, 'months')], now), 100);
    expect(monthlyFixedCosts([charge(12, 1, 'weeks')], now), closeTo(52, .001));
    expect(monthlyFixedCosts([charge(1, 1, 'days')], now), closeTo(30.42, .01));
  });

  test('income and what already ended stay out', () {
    expect(
        monthlyFixedCosts([
          charge(100, 1, 'months', type: 'income'),
          charge(100, 1, 'months', end: DateTime(2026, 10, 1)),
        ], now),
        0);
  });

  test('the target is months of fixed costs plus food', () {
    const plan = EmergencyPlan(goalId: 'g', months: 6, foodMinimum: 200);
    expect(plan.target([charge(700, 1, 'months')], now), 5400);
  });
}
