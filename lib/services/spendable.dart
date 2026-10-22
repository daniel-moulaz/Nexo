import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'budget_insights.dart';
import 'finance_rules.dart';
import 'recurring_projection.dart';

/// "Quanto posso gastar" for the month: fixed income (recurring) minus fixed
/// bills (recurring), pending bills of the month, what goals need this month
/// and the variable spending already done. Extra income does not count:
/// it is a bonus, not a plan.
class Spendable {
  const Spendable(
      {required this.fixedIncome,
      required this.fixedBills,
      required this.pendingBills,
      required this.goals,
      required this.variableSpent,
      required this.daysLeft});
  final double fixedIncome, fixedBills, pendingBills, goals, variableSpent;
  final int daysLeft;

  double get free =>
      fixedIncome - fixedBills - pendingBills - goals - variableSpent;
  double get perDay => free <= 0 ? 0 : free / daysLeft;

  /// Without a recurring income there is no base to plan on.
  bool get hasBase => fixedIncome > 0;
}

bool _isRecurring(AppTransaction t, TransactionMetadata? m) =>
    t.id.startsWith('recurring:') || m?.source == 'recurring';

Spendable spendable({
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required List<RecurringPayment> recurring,
  required List<SavingsGoal> goals,
  required double Function(AppTransaction) toMain,
  required double Function(double amount, String currency) convert,
  required String Function(RecurringPayment) currencyOf,
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime(today.year, today.month);
  final end = DateTime(today.year, today.month + 1); // exclusive
  var fixedIncome = 0.0, fixedBills = 0.0, pending = 0.0, variable = 0.0;
  for (final t in transactions) {
    if (t.date.isBefore(start) || !t.date.isBefore(end)) continue;
    final m = metadata[t.id];
    if (FinanceRules.isNeutral(t, m)) continue;
    final value = toMain(t);
    final recurringEntry = _isRecurring(t, m);
    if (m?.isPending == true) {
      if (t.type == 'expense') pending += value;
      if (t.type == 'income' && recurringEntry) fixedIncome += value;
      continue;
    }
    if (t.type == 'income') {
      if (recurringEntry) fixedIncome += value;
    } else if (t.type == 'expense') {
      if (recurringEntry) {
        fixedBills += value;
      } else {
        variable += value;
      }
    }
  }
  // What recurring items still have to happen this month.
  final registered = {for (final t in transactions) t.id};
  for (final o in RecurringProjection.calculate(recurring,
          until: end.subtract(const Duration(days: 1)),
          registeredIds: registered)
      .occurrences) {
    if (o.date.isBefore(start)) continue; // overdue: not this month's plan
    final value = convert(o.amount, currencyOf(o.recurring));
    if (o.recurring.paymentType == 'income') {
      fixedIncome += value;
    } else {
      fixedBills += value;
    }
  }
  var goalsMonth = 0.0;
  for (final g in goals) {
    goalsMonth += convert(goalMonthlyNeeded(g, now) ?? 0, g.currency);
  }
  return Spendable(
      fixedIncome: fixedIncome,
      fixedBills: fixedBills,
      pendingBills: pending,
      goals: goalsMonth,
      variableSpent: variable,
      daysLeft: end.difference(today).inDays);
}
