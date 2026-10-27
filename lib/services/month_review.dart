import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'financial_analysis.dart';

/// A closed (or current) month told as highlights, compared with the month
/// before, by the same rules as every report: transfers, reserves and
/// pending entries are not spending; refunds are not income.
class MonthReview {
  MonthReview._(this.month, this.current, this.previous, this.daysCounted,
      this._amount, this.budgets);

  final DateTime month;
  final FinancialAnalysis current, previous;

  /// Days of the month already lived (all of them for a past month).
  final int daysCounted;
  final double Function(AppTransaction) _amount;

  /// Monthly budgets: (budget, spent in the month, limit of the month).
  final List<(Budget, double, double)> budgets;

  factory MonthReview.build({
    required Iterable<AppTransaction> transactions,
    required Map<String, TransactionMetadata> metadata,
    required double Function(AppTransaction) amount,
    required DateTime month,
    required DateTime now,
    List<Budget> budgetList = const [],
  }) {
    final start = DateTime(month.year, month.month);
    final last = DateTime(month.year, month.month + 1, 0);
    final today = DateTime(now.year, now.month, now.day);
    final current =
        !today.isBefore(start) && !today.isAfter(last) ? today : last;
    FinancialAnalysis of(DateTime from, DateTime to) => FinancialAnalysis(
        transactions: transactions,
        metadata: metadata,
        filter: AnalysisFilter(from: from, to: to),
        amount: amount);
    final now0 = of(start, current);
    final prev = of(DateTime(month.year, month.month - 1),
        DateTime(month.year, month.month, 0));
    final days = last.day;
    final budgets = <(Budget, double, double)>[];
    for (final b in budgetList.where((b) => b.period != 'weekly')) {
      final created =
          DateTime(b.createdAt.year, b.createdAt.month, b.createdAt.day);
      if (created.isAfter(last)) continue;
      // Created during this month: counted from that day, prorated.
      final from = created.isAfter(start) ? created : start;
      final limit = created.isAfter(start)
          ? (b.amount * (days - created.day + 1) / days * 100).round() / 100
          : b.amount;
      final spent = of(from, current).categories[b.categoryId] ?? 0;
      budgets.add((b, spent, limit));
    }
    return MonthReview._(start, now0, prev, current.day, amount, budgets);
  }

  double get spent => current.expense;
  double get previousSpent => previous.expense;

  /// Percent change in usual spending against the whole previous month
  /// (one-off expenses left out); null without a base.
  double? get change => current.changeFrom(previous);

  /// One-off expenses of the month, outside the comparison.
  double get oneOff => current.extraordinary;

  /// What the comparison is made against: last month without its one-offs.
  double get previousUsual => previous.normal;

  /// Whether one-off expenses were left out on either side.
  bool get comparesWithoutOneOffs =>
      current.extraordinary > 0 || previous.extraordinary > 0;

  double get result => current.result;
  double get fixedIncome => current.fixedIncome;
  double get extraIncome => current.extraIncome;

  int get quietDays =>
      daysCounted - current.dailyExpense.values.where((v) => v > 0).length;

  /// Top categories with the previous month's value for each.
  List<(String, double, double)> topCategories([int n = 3]) => [
        for (final e in current.topCategories.take(n))
          (e.key, e.value, previous.categories[e.key] ?? 0)
      ];

  AppTransaction? get biggest {
    AppTransaction? best;
    for (final t in current.realized) {
      if (t.type != 'expense') continue;
      if (best == null || _amount(t) > _amount(best)) best = t;
    }
    return best;
  }

  double amountOf(AppTransaction t) => _amount(t);

  /// Weekday (1 = Monday) with the most spending, or null.
  int? get busiestWeekday {
    final byDay = <int, double>{};
    current.dailyExpense.forEach(
        (d, v) => byDay.update(d.weekday, (x) => x + v, ifAbsent: () => v));
    if (byDay.isEmpty) return null;
    return (byDay.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
        .first
        .key;
  }

  int get budgetsKept => budgets.where((b) => b.$2 <= b.$3 + .005).length;
}
