import 'cash_forecast.dart';

class CashTimelinePoint {
  final DateTime date;
  final double balance;
  const CashTimelinePoint(this.date, this.balance);
}

/// First point: now. Other points: end-of-day balances from the existing forecast.
/// Overdue movements enter today exactly once. No ledger writes or estimates.
class CashTimeline {
  final List<CashTimelinePoint> points;
  final double outflow, inflow;
  final List<ForecastEvent> overdue, upcoming;
  const CashTimeline(
      this.points, this.outflow, this.inflow, this.overdue, this.upcoming);
  CashTimelinePoint get lowest =>
      points.reduce((a, b) => a.balance <= b.balance ? a : b);
  static CashTimeline build(CashForecast forecast,
      {required DateTime now,
      required int days,
      required double Function(double, String) convert}) {
    if (days < 0 || days > 366) throw ArgumentError.value(days, 'days');
    final today = DateTime(now.year, now.month, now.day);
    final end = DateTime(today.year, today.month, today.day + days);
    final daily = <DateTime, double>{};
    final overdue = <ForecastEvent>[], upcoming = <ForecastEvent>[];
    double outflow = 0, inflow = 0;
    for (final e in forecast.events) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      if (e.amount == 0 || day.isAfter(end)) continue;
      final amount = convert(e.amount, e.currency);
      if (amount < 0) outflow -= amount;
      if (amount > 0) inflow += amount;
      if (day.isBefore(today)) {
        overdue.add(e);
      } else {
        upcoming.add(e);
      }
      final effectiveDay = day.isBefore(today) ? today : day;
      daily.update(effectiveDay, (v) => v + amount, ifAbsent: () => amount);
    }
    int byDate(ForecastEvent a, ForecastEvent b) => a.date.compareTo(b.date);
    overdue.sort(byDate);
    upcoming.sort(byDate);
    var balance = forecast.current;
    final points = [CashTimelinePoint(today, balance)];
    for (var i = 0; i <= days; i++) {
      final day = DateTime(today.year, today.month, today.day + i);
      balance += daily[day] ?? 0;
      points.add(CashTimelinePoint(day, balance));
    }
    return CashTimeline(List.unmodifiable(points), outflow, inflow,
        List.unmodifiable(overdue), List.unmodifiable(upcoming));
  }
}
