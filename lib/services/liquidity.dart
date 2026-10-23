import '../investments/investment_models.dart';
import '../models/models.dart';
import 'cash_forecast.dart';
import 'cash_timeline.dart';

// ── Business days ────────────────────────────────────────────────────────

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// Easter Sunday (Meeus/Jones/Butcher, Gregorian calendar).
DateTime easter(int year) {
  final a = year % 19, b = year ~/ 100, c = year % 100;
  final d = b ~/ 4, e = b % 4, f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = (h + l - 7 * m + 114) % 31 + 1;
  return DateTime(year, month, day);
}

/// Days without settlement in the Brazilian market: national holidays,
/// Carnival, Good Friday, Corpus Christi and the B3 closings on 24 and 31
/// December. Computed on the device; no network needed.
Set<DateTime> marketHolidays(int year) {
  final e = easter(year);
  return {
    for (final (m, d) in const [
      (1, 1), (4, 21), (5, 1), (9, 7), (10, 12), (11, 2), (11, 15), //
      (11, 20), (12, 24), (12, 25), (12, 31),
    ])
      DateTime(year, m, d),
    e.subtract(const Duration(days: 48)), // Carnival Monday
    e.subtract(const Duration(days: 47)), // Carnival Tuesday
    e.subtract(const Duration(days: 2)), // Good Friday
    e.add(const Duration(days: 60)), // Corpus Christi
  };
}

bool isBusinessDay(DateTime d) =>
    d.weekday != DateTime.saturday &&
    d.weekday != DateTime.sunday &&
    !marketHolidays(d.year).contains(_day(d));

DateTime nextBusinessDay(DateTime d) {
  var x = _day(d);
  while (!isBusinessDay(x)) {
    x = x.add(const Duration(days: 1));
  }
  return x;
}

DateTime addBusinessDays(DateTime d, int n) {
  var x = _day(d);
  for (var left = n; left > 0;) {
    x = x.add(const Duration(days: 1));
    if (isBusinessDay(x)) left--;
  }
  return x;
}

// ── When money becomes available ─────────────────────────────────────────

/// How a kind of asset turns into money. Equities settle in D+2 business
/// days at B3 (configurable: B3 studies D+1); Tesouro Direto and daily
/// liquidity fixed income pay the same day when sold before 13:00 on a
/// business day; reserves in the Nexo are immediate. Unknown kinds give no
/// date instead of a guess.
class SettlementRule {
  const SettlementRule({this.equityDays = 2, this.cutoffHour = 13});
  final int equityDays;
  final int cutoffHour;

  /// When the money is in the account if the order is placed at [when].
  DateTime? availableOn(String assetClass, DateTime when) {
    final today = _day(when);
    switch (assetClass) {
      case 'Ações':
      case 'FIIs':
      case 'ETFs':
        // An order on a non-business day counts from the next one.
        final trade = isBusinessDay(today) ? today : nextBusinessDay(today);
        return addBusinessDays(trade, equityDays);
      case 'Renda fixa':
        final sameDay = isBusinessDay(today) && when.hour < cutoffHour;
        return sameDay ? today : addBusinessDays(today, 1);
      case 'reserva':
        return today;
      default:
        return null;
    }
  }

  /// Last day to place the order so the money is there on [due] (null when
  /// it is already too late or the kind is unknown).
  DateTime? sellBy(String assetClass, DateTime due, DateTime now) {
    final target = _day(due);
    final first = availableOn(assetClass, now);
    if (first == null || first.isAfter(target)) return null;
    // Walk back from the due date to the last order day that still works.
    for (var d = target;
        !d.isBefore(_day(now));
        d = d.subtract(const Duration(days: 1))) {
      final on = availableOn(assetClass, DateTime(d.year, d.month, d.day, 10));
      if (on != null &&
          !on.isAfter(target) &&
          (isBusinessDay(d) || assetClass == 'reserva')) {
        return d;
      }
    }
    return _day(now);
  }
}

/// Money that can be raised by a date: positions and reserves with when
/// they would arrive.
class RaiseOption {
  const RaiseOption(
      {required this.label,
      required this.kind,
      required this.amount,
      required this.availableOn,
      required this.sellBy});
  final String label, kind;
  final double amount;
  final DateTime? availableOn, sellBy;
  bool get inTime => sellBy != null;
}

List<RaiseOption> raiseBy({
  required DateTime due,
  required DateTime now,
  required List<InvestmentPosition> positions,
  required List<SavingsGoal> goals,
  SettlementRule rule = const SettlementRule(),
}) {
  final out = <RaiseOption>[];
  for (final g in goals) {
    if (g.currentAmount <= .005) continue;
    out.add(RaiseOption(
        label: g.name,
        kind: 'reserva',
        amount: g.currentAmount,
        availableOn: rule.availableOn('reserva', now),
        sellBy: rule.sellBy('reserva', due, now)));
  }
  for (final p in positions) {
    if (p.investment.archived || p.value <= 0) continue;
    final cls = p.investment.assetClass;
    out.add(RaiseOption(
        label: p.investment.name,
        kind: cls,
        amount: p.value / 100,
        availableOn: rule.availableOn(cls, now),
        sellBy: rule.sellBy(cls, due, now)));
  }
  out.sort((a, b) => (b.inTime ? 1 : 0) - (a.inTime ? 1 : 0));
  return out;
}

// ── Shortfall before a due date ──────────────────────────────────────────

/// A bill that the cash will not cover on its due date.
class Shortfall {
  const Shortfall(this.event, this.missing, this.balanceAfter);
  final ForecastEvent event;

  /// How much is missing to pay it (positive).
  final double missing;
  final double balanceAfter;
}

/// The first outflows (invoices first) after which the forecast balance is
/// below zero, from the same timeline the home already shows.
List<Shortfall> shortfalls(CashTimeline timeline,
    {double Function(double, String)? convert, int max = 3}) {
  final byDay = {
    for (final p in timeline.points.skip(1)) _day(p.date): p.balance
  };
  final out = <Shortfall>[];
  final seen = <DateTime>{};
  final events = [...timeline.upcoming]
    ..sort((a, b) => a.kind == 'invoice' && b.kind != 'invoice'
        ? -1
        : b.kind == 'invoice' && a.kind != 'invoice'
            ? 1
            : a.date.compareTo(b.date));
  for (final e in events) {
    final day = _day(e.date);
    final balance = byDay[day];
    if (e.amount >= 0 ||
        balance == null ||
        balance >= 0 ||
        seen.contains(day)) {
      continue;
    }
    final amount = convert?.call(-e.amount, e.currency) ?? -e.amount;
    seen.add(day);
    out.add(Shortfall(e, -balance < amount ? -balance : amount, balance));
    if (out.length == max) break;
  }
  out.sort((a, b) => a.event.date.compareTo(b.event.date));
  return out;
}
