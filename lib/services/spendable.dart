import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'budget_insights.dart';
import 'finance_rules.dart';
import 'recurring_projection.dart';

/// "Quanto posso gastar": fixed income minus fixed bills, pending bills, what
/// goals need, the monthly share of yearly bills and the variable spending
/// already done. Extra income does not count: it is a bonus, not a plan.
///
/// The horizon is **the next main income**, not the calendar month: someone
/// paid on the 7th plans from one payday to the next. Without a recurring
/// income the horizon falls back to the end of the month.
class Spendable {
  const Spendable(
      {required this.fixedIncome,
      required this.fixedBills,
      required this.pendingBills,
      required this.goals,
      required this.reserved,
      required this.variableSpent,
      required this.upcomingBills,
      required this.daysLeft,
      required this.since,
      required this.until,
      required this.untilNextIncome,
      required this.incomeExpected});
  final double fixedIncome, fixedBills, pendingBills, goals, variableSpent;

  /// Monthly share of bills that come less than once a month (IPVA,
  /// insurance, tuition) and are not due inside this cycle.
  final double reserved;

  /// Fixed and pending bills still to be paid before [until].
  final double upcomingBills;
  final int daysLeft;

  /// The cycle: from the last main income (or the 1st) to [until], exclusive.
  final DateTime since, until;

  /// True when [until] is the next main income; false for the month's end.
  final bool untilNextIncome;

  /// The cycle's main income is projected but not registered yet (late pay).
  final bool incomeExpected;

  double get free =>
      fixedIncome -
      fixedBills -
      pendingBills -
      goals -
      reserved -
      variableSpent;
  double get perDay => free <= 0 ? 0 : free / daysLeft;

  /// Without a recurring income there is no base to plan on.
  bool get hasBase => fixedIncome > 0;
}

/// The recurring income that sets the cycle: the largest one.
RecurringPayment? mainIncome(List<RecurringPayment> recurring,
    {required double Function(double amount, String currency) convert,
    required String Function(RecurringPayment) currencyOf}) {
  RecurringPayment? main;
  for (final r in recurring) {
    if (r.paymentType != 'income') continue;
    if (main == null ||
        convert(r.amount, currencyOf(r)) >
            convert(main.amount, currencyOf(main))) {
      main = r;
    }
  }
  return main;
}

bool _isRecurring(AppTransaction t, TransactionMetadata? m) =>
    t.id.startsWith('recurring:') ||
    (m?.source.startsWith('recurring') ?? false);

/// Months between occurrences; null when the bill comes monthly or more often.
int? _monthsBetween(RecurringPayment r) {
  switch (r.freqUnit) {
    case 'years':
      return 12 * r.freqVal;
    case 'months':
      return r.freqVal > 1 ? r.freqVal : null;
    default:
      return null;
  }
}

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
  final monthStart = DateTime(today.year, today.month);
  final monthEnd = DateTime(today.year, today.month + 1); // exclusive
  final registered = {for (final t in transactions) t.id};

  // ── The main income sets the cycle ──
  final main = mainIncome(recurring, convert: convert, currencyOf: currencyOf);
  var since = monthStart;
  var until = monthEnd;
  var untilNextIncome = false;
  var incomeExpected = false;
  var expectedIncome = 0.0;
  if (main != null) {
    // Registered occurrences: by id, or a manual entry the person marked as
    // this income ("é a renda do mês").
    DateTime? lastRegistered;
    for (final t in transactions) {
      final m = metadata[t.id];
      final mine = t.id.startsWith('recurring:${main.id}:') ||
          m?.source == 'recurring:${main.id}';
      if (!mine || t.date.isAfter(now)) continue;
      final d = DateTime(t.date.year, t.date.month, t.date.day);
      if (lastRegistered == null || d.isAfter(lastRegistered)) {
        lastRegistered = d;
      }
    }
    final projected = RecurringProjection.calculate([main],
            until: today.add(const Duration(days: 400)),
            registeredIds: registered)
        .occurrences
        .where((o) => !_coveredByManual(o, transactions, metadata, main))
        .toList();
    DateTime? next;
    RecurringOccurrence? overdue;
    for (final o in projected) {
      if (o.date.isAfter(today)) {
        next ??= o.date;
      } else if (overdue == null || o.date.isAfter(overdue.date)) {
        overdue = o;
      }
    }
    if (lastRegistered != null &&
        (overdue == null || !overdue.date.isAfter(lastRegistered))) {
      since = lastRegistered;
    } else if (overdue != null &&
        !overdue.date.isBefore(monthStart.subtract(const Duration(days: 31)))) {
      // The pay is late: plan on it, and say so.
      since = overdue.date;
      incomeExpected = true;
      expectedIncome = convert(overdue.amount, currencyOf(main));
    }
    if (next != null) {
      until = next;
      untilNextIncome = true;
    }
    if (!until.isAfter(today)) {
      until = today.add(const Duration(days: 1));
    }
  }

  bool inCycle(DateTime d) => !d.isBefore(since) && d.isBefore(until);

  // ── What already happened in the cycle ──
  var fixedIncome = expectedIncome,
      fixedBills = 0.0,
      pending = 0.0,
      variable = 0.0;
  var upcoming = 0.0;
  for (final t in transactions) {
    final m = metadata[t.id];
    if (FinanceRules.isNeutral(t, m)) continue;
    final value = toMain(t);
    final recurringEntry = _isRecurring(t, m);
    if (m?.isPending == true) {
      final due = m?.dueDate ?? t.date;
      if (t.type == 'expense' &&
          inCycle(DateTime(due.year, due.month, due.day))) {
        pending += value;
        if (!due.isBefore(today)) upcoming += value;
      }
      if (t.type == 'income' && recurringEntry && inCycle(t.date)) {
        fixedIncome += value;
      }
      continue;
    }
    if (!inCycle(t.date) || t.date.isAfter(now)) continue;
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

  // ── What is still to come before the horizon ──
  final others = recurring.where((r) => r != main);
  for (final o in RecurringProjection.calculate(others,
          until: until.subtract(const Duration(days: 1)),
          registeredIds: registered)
      .occurrences) {
    if (!inCycle(o.date)) continue; // older than the cycle: not this plan
    final value = convert(o.amount, currencyOf(o.recurring));
    if (o.recurring.paymentType == 'income') {
      fixedIncome += value;
    } else {
      fixedBills += value;
      if (!o.date.isBefore(today)) upcoming += value;
    }
  }

  // ── Goals and yearly bills, as a share of this cycle ──
  final cycleDays = until.difference(since).inDays.clamp(1, 1 << 20);
  final monthDays = DateTime(since.year, since.month + 1, 0).day;
  final share = cycleDays / monthDays;
  var goalsCycle = 0.0;
  for (final g in goals) {
    goalsCycle += convert(goalMonthlyNeeded(g, now) ?? 0, g.currency) * share;
  }
  var reserved = 0.0;
  for (final r in recurring) {
    if (r.paymentType != 'expense') continue;
    final months = _monthsBetween(r);
    if (months == null) continue;
    final dueInCycle = RecurringProjection.calculate([r],
            until: until.subtract(const Duration(days: 1)),
            registeredIds: registered)
        .occurrences
        .any((o) => inCycle(o.date));
    if (dueInCycle) continue; // paid in full this cycle, counted above
    reserved += convert(r.amount, currencyOf(r)) / months * share;
  }

  return Spendable(
      fixedIncome: fixedIncome,
      fixedBills: fixedBills,
      pendingBills: pending,
      goals: goalsCycle,
      reserved: reserved,
      variableSpent: variable,
      upcomingBills: upcoming,
      daysLeft: until.difference(today).inDays.clamp(1, 1 << 20),
      since: since,
      until: until,
      untilNextIncome: untilNextIncome,
      incomeExpected: incomeExpected);
}

/// A manual income the person marked as this recurring income, dated near
/// the occurrence, stands for it.
bool _coveredByManual(RecurringOccurrence o, List<AppTransaction> transactions,
    Map<String, TransactionMetadata> metadata, RecurringPayment main) {
  for (final t in transactions) {
    if (metadata[t.id]?.source != 'recurring:${main.id}') continue;
    if (t.date.difference(o.date).inDays.abs() <= 10) return true;
  }
  return false;
}

/// The "is this the month's income?" question: a manual income near the
/// size of the main recurring income, arrived in the last days, while the
/// cycle's income is still missing. Null when there is nothing to ask.
AppTransaction? incomeToConfirm({
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required List<RecurringPayment> recurring,
  required double Function(AppTransaction) toMain,
  required double Function(double amount, String currency) convert,
  required String Function(RecurringPayment) currencyOf,
  required DateTime now,
}) {
  final main = mainIncome(recurring, convert: convert, currencyOf: currencyOf);
  if (main == null) return null;
  final expected = convert(main.amount, currencyOf(main));
  final today = DateTime(now.year, now.month, now.day);
  final windowStart = today.subtract(const Duration(days: 10));
  // Already registered this cycle: nothing to ask.
  for (final t in transactions) {
    final m = metadata[t.id];
    if ((t.id.startsWith('recurring:${main.id}:') ||
            m?.source == 'recurring:${main.id}') &&
        !t.date.isBefore(windowStart.subtract(const Duration(days: 20)))) {
      return null;
    }
  }
  AppTransaction? best;
  for (final t in transactions) {
    final m = metadata[t.id];
    if (t.type != 'income' ||
        t.date.isBefore(windowStart) ||
        t.date.isAfter(now)) continue;
    if (_isRecurring(t, m) || FinanceRules.isNeutral(t, m)) continue;
    if ((m?.source ?? 'manual') != 'manual' &&
        m?.source != 'import' &&
        m?.source != 'pluggy') continue;
    if (toMain(t) < expected * .5) continue;
    if (best == null || t.date.isAfter(best.date)) best = t;
  }
  return best;
}
