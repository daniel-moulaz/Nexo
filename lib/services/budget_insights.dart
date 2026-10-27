import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'finance_rules.dart';

/// The period a budget measures now. A budget created in the middle of a
/// period counts only from its creation day, with a proportional limit, so
/// it is not born over the limit because of what was spent before it.
class BudgetWindow {
  const BudgetWindow(this.start, this.end, this.countsFrom, this.limit);
  final DateTime start;

  /// Exclusive.
  final DateTime end;
  final DateTime countsFrom;
  final double limit;
  bool get partial => countsFrom.isAfter(start);
}

BudgetWindow budgetWindow(Budget b, DateTime now,
    {String weekStart = 'monday'}) {
  final today = DateTime(now.year, now.month, now.day);
  final DateTime start, end;
  if (b.period == 'weekly') {
    final offset = weekStart == 'monday' ? now.weekday - 1 : now.weekday % 7;
    start = DateTime(today.year, today.month, today.day - offset);
    end = DateTime(start.year, start.month, start.day + 7);
  } else {
    start = DateTime(today.year, today.month);
    end = DateTime(today.year, today.month + 1);
  }
  final created =
      DateTime(b.createdAt.year, b.createdAt.month, b.createdAt.day);
  if (!created.isAfter(start) || !created.isBefore(end)) {
    return BudgetWindow(start, end, start, b.amount);
  }
  final days = end.difference(start).inDays;
  final left = end.difference(created).inDays;
  final limit = (b.amount * left / days * 100).roundToDouble() / 100;
  return BudgetWindow(start, end, created, limit);
}

/// How a budget is doing against the time left in its period.
class BudgetPace {
  const BudgetPace(
      {required this.daysLeft, required this.perDay, this.projection});

  /// Days left in the period, today included.
  final int daysLeft;

  /// What can still be spent per day without passing the limit (0 if over).
  final double perDay;

  /// Month total at the current pace; null for weekly budgets and in the
  /// first days of the month, when the pace says little.
  final double? projection;
}

BudgetPace budgetPace(Budget b, double spent, DateTime now,
    {String weekStart = 'monday', double? limit}) {
  final today = DateTime(now.year, now.month, now.day);
  final int daysLeft;
  double? projection;
  if (b.period == 'weekly') {
    final offset =
        weekStart == 'monday' ? now.weekday - 1 : now.weekday % 7; // 0..6
    daysLeft = 7 - offset;
  } else {
    final days = DateTime(now.year, now.month + 1, 0).day;
    daysLeft = days - today.day + 1;
    if (today.day >= 7) projection = spent / today.day * days;
  }
  final left = (limit ?? b.amount) - spent;
  return BudgetPace(
      daysLeft: daysLeft,
      perDay: left <= 0 ? 0 : left / daysLeft,
      projection: projection);
}

class BudgetSuggestion {
  const BudgetSuggestion(this.category, this.average, this.amount);
  final AppCategory category;

  /// Average spent per month in the last three full months.
  final double average;

  /// Suggested limit: the average rounded up to a round number.
  final double amount;
}

/// Expense categories with regular spending and no budget yet, largest first.
/// Transfers, reserves and invoice payments never count as spending.
List<BudgetSuggestion> suggestBudgets({
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required List<AppCategory> categories,
  required List<Budget> budgets,
  required double Function(AppTransaction) toMain,
  required DateTime now,
  int max = 3,
}) {
  final from = DateTime(now.year, now.month - 3);
  final to = DateTime(now.year, now.month);
  final budgeted = budgets.map((b) => b.categoryId).toSet();
  final totals = <String, double>{};
  final months = <String, Set<int>>{};
  for (final t in transactions) {
    if (t.type != 'expense' ||
        budgeted.contains(t.categoryId) ||
        t.date.isBefore(from) ||
        !t.date.isBefore(to) ||
        FinanceRules.isNeutral(t, metadata[t.id]) ||
        metadata[t.id]?.expenseClass == 'extraordinary') {
      continue;
    }
    totals[t.categoryId] = (totals[t.categoryId] ?? 0) + toMain(t);
    (months[t.categoryId] ??= {}).add(t.date.year * 12 + t.date.month);
  }
  final out = <BudgetSuggestion>[];
  for (final c in categories) {
    if (c.type != 'expense') continue;
    final total = totals[c.id] ?? 0;
    // Spending in at least two of the three months: a habit, not a one-off.
    if ((months[c.id]?.length ?? 0) < 2) continue;
    final average = total / 3;
    if (average < 50) continue;
    final step = average >= 1000 ? 100.0 : 50.0;
    out.add(BudgetSuggestion(c, average, (average / step).ceil() * step));
  }
  out.sort((a, b) => b.average.compareTo(a.average));
  return out.take(max).toList();
}

/// How much to put aside each month to reach [goal] by its date, or null
/// without a date or when it is already reached.
double? goalMonthlyNeeded(SavingsGoal goal, DateTime now) {
  final date = goal.targetDate;
  final missing = goal.targetAmount - goal.currentAmount;
  if (date == null || missing <= 0 || goal.isCompleted) return null;
  var months = (date.year - now.year) * 12 + date.month - now.month;
  if (date.day >= now.day) months += 1;
  return missing / (months < 1 ? 1 : months);
}
