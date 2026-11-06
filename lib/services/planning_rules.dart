import '../models/models.dart';

/// A budget that grows with what its own activity earns: a base, plus a share
/// of the month's profit. The base is the floor: a loss never lowers it.
class BudgetRule {
  const BudgetRule(
      {required this.base,
      required this.percent,
      required this.incomeCategoryId});
  final double base, percent;

  /// Where the earnings are recorded; the budget's category holds the costs.
  final String incomeCategoryId;

  static BudgetRule? fromJson(Object? value) {
    if (value is! Map) return null;
    final base = value['base'], percent = value['percent'];
    final income = value['income_category_id'];
    if (base is! num || percent is! num || income is! String) return null;
    return BudgetRule(
        base: base.toDouble(),
        percent: percent.toDouble(),
        incomeCategoryId: income);
  }

  Map<String, Object> toJson() => {
        'base': base,
        'percent': percent,
        'income_category_id': incomeCategoryId
      };

  BudgetRuleResult apply({required double earned, required double spent}) {
    final profit = earned - spent;
    return BudgetRuleResult(
        rule: this,
        earned: earned,
        spent: spent,
        profit: profit,
        limit: base + (profit > 0 ? profit * percent / 100 : 0));
  }
}

class BudgetRuleResult {
  const BudgetRuleResult(
      {required this.rule,
      required this.earned,
      required this.spent,
      required this.profit,
      required this.limit});
  final BudgetRule rule;
  final double earned, spent, profit, limit;
}

/// A goal whose target follows the fixed costs: [months] of what the
/// recurring expenses cost a month, plus a minimum for food.
class EmergencyPlan {
  const EmergencyPlan(
      {required this.goalId, required this.months, required this.foodMinimum});
  final String goalId;
  final int months;
  final double foodMinimum;

  static EmergencyPlan? fromJson(Object? value) {
    if (value is! Map) return null;
    final goal = value['goal_id'], months = value['months'];
    final food = value['food_minimum'];
    if (goal is! String || months is! num || food is! num) return null;
    return EmergencyPlan(
        goalId: goal, months: months.toInt(), foodMinimum: food.toDouble());
  }

  Map<String, Object> toJson() =>
      {'goal_id': goalId, 'months': months, 'food_minimum': foodMinimum};

  double target(List<RecurringPayment> recurring, DateTime now) =>
      months * (monthlyFixedCosts(recurring, now) + foodMinimum);
}

/// What the recurring expenses still running cost in an average month.
double monthlyFixedCosts(List<RecurringPayment> recurring, DateTime now) {
  var total = 0.0;
  for (final r in recurring) {
    if (r.paymentType == 'income' || r.freqVal <= 0) continue;
    if (r.endDate != null && r.endDate!.isBefore(now)) continue;
    total += switch (r.freqUnit) {
      'days' => r.amount * 365 / 12 / r.freqVal,
      'weeks' => r.amount * 52 / 12 / r.freqVal,
      'years' => r.amount / 12 / r.freqVal,
      _ => r.amount / r.freqVal,
    };
  }
  return total;
}
