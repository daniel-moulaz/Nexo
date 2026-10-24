import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'financial_analysis.dart';

/// This week so far against the same days of last week, with the rules of
/// [FinancialAnalysis]: transfers, reserves and pending entries are not
/// spending, refunds are not income.
class WeekSummary {
  WeekSummary._(
      this.start, this.today, this.current, this.previous, this._amount);

  final DateTime start, today;
  final FinancialAnalysis current, previous;
  final double Function(AppTransaction) _amount;

  static DateTime startOf(DateTime now, String weekStart) {
    final offset =
        weekStart == 'monday' ? now.weekday - 1 : now.weekday % 7; // 0..6
    return DateTime(now.year, now.month, now.day - offset);
  }

  factory WeekSummary.build(
      {required Iterable<AppTransaction> transactions,
      required Map<String, TransactionMetadata> metadata,
      required double Function(AppTransaction) amount,
      required DateTime now,
      String weekStart = 'monday'}) {
    final today = DateTime(now.year, now.month, now.day);
    final start = startOf(today, weekStart);
    FinancialAnalysis of(DateTime from, DateTime to) => FinancialAnalysis(
        transactions: transactions,
        metadata: metadata,
        filter: AnalysisFilter(from: from, to: to),
        amount: amount);
    return WeekSummary._(
        start,
        today,
        of(start, today),
        of(start.subtract(const Duration(days: 7)),
            today.subtract(const Duration(days: 7))),
        amount);
  }

  double get spent => current.expense;
  double get previousSpent => previous.expense;

  /// Percent change against the same days of last week; null without a base.
  double? get change => current.changeFrom(previous);

  int get daysElapsed => today.difference(start).inDays + 1;

  /// Days of the week so far with no counted spending.
  int get quietDays =>
      daysElapsed - current.dailyExpense.values.where((v) => v > 0).length;

  /// Counted spending for each day of the week, the future ones at zero.
  List<double> get days => [
        for (var i = 0; i < 7; i++)
          current.dailyExpense[
                  DateTime(start.year, start.month, start.day + i)] ??
              0
      ];

  MapEntry<String, double>? get topCategory =>
      current.topCategories.isEmpty ? null : current.topCategories.first;

  AppTransaction? get biggest {
    AppTransaction? best;
    for (final t in current.realized) {
      if (t.type != 'expense') continue;
      if (best == null || _amount(t) > _amount(best)) best = t;
    }
    return best;
  }

  double amountOf(AppTransaction t) => _amount(t);
}
