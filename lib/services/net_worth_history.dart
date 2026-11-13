import '../investments/investment_models.dart';
import '../models/models.dart';
import '../models/transaction_metadata.dart';

/// One month-end of what the person has: accounts and cards, investments at
/// cost, and everything else (bens, dívidas, dinheiro emprestado, objetivos).
class NetWorthPoint {
  const NetWorthPoint(
      {required this.month,
      required this.cash,
      required this.invested,
      required this.others,
      required this.income});
  final DateTime month;
  final double cash, invested, others, income;
  double get total => cash + invested + others;
}

/// Everything net worth is made of. The app, the cards and the charts read
/// this one rule, so they cannot disagree.
class NetWorthInputs {
  const NetWorthInputs({
    required this.accounts,
    required this.transactions,
    required this.metadata,
    required this.positions,
    required this.convert,
    this.assets = const [],
    this.loans = const [],
    this.loanPayments = const [],
    this.lended = const [],
    this.goals = const [],
    this.contributions = const [],
  });
  final List<Account> accounts;
  final List<AppTransaction> transactions;
  final Map<String, TransactionMetadata> metadata;
  final List<InvestmentPosition> positions;
  final double Function(double amount, String currency) convert;
  final List<AssetItem> assets;
  final List<Loan> loans;
  final List<LoanPayment> loanPayments;
  final List<LendedMoney> lended;
  final List<SavingsGoal> goals;
  final List<SavingsContribution> contributions;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime _localDay(DateTime d) => _day(d.toLocal());

  /// Past the last entry: the state of things right now.
  static final now = DateTime(9999);

  double _goalValue(SavingsContribution c) {
    final goal = goals.where((g) => g.id == c.goalId).firstOrNull;
    return goal == null ? c.amount : convert(c.amount, goal.currency);
  }

  /// A goal's movement only took money from an account when it names one;
  /// without it the reserve was bookkeeping and the money never left.
  Iterable<SavingsContribution> get _goalMoves =>
      contributions.where((c) => c.accountId.isNotEmpty);

  /// Investments at cost on [end]: a sale takes out what those shares cost,
  /// not what they sold for, the same rule as the position itself.
  double costAt(DateTime end) {
    var cents = 0;
    for (final p in positions) {
      cents += InvestmentPosition(p.investment,
          p.operations.where((o) => !_localDay(o.date).isAfter(end))).cost;
    }
    return cents / 100;
  }

  /// Investments at the last known price. There is no price history, so this
  /// only exists for today.
  double get marketValue =>
      positions.fold<int>(0, (sum, p) => sum + p.value) / 100;

  /// Bens on [end], from the day they were registered.
  double assetsAt(DateTime end) => assets
      .where((a) => !_day(a.createdAt).isAfter(end))
      .fold(0.0, (sum, a) => sum + convert(a.value, a.currency));

  /// Money reserved in goals, debts and money lent, on [end]. Nothing records
  /// the day something was settled, so what is settled today is left out of
  /// past months as well.
  double claimsAt(DateTime end) {
    var total = 0.0;
    for (final c in _goalMoves) {
      if (_day(c.date).isAfter(end)) continue;
      final value = _goalValue(c);
      total += c.type == 'withdrawal' ? -value : value;
    }
    for (final l in lended) {
      if (l.isSettled || _day(l.date).isAfter(end)) continue;
      total += l.type == 'borrowed' ? -l.amount : l.amount;
    }
    for (final l in loans) {
      if (l.isSettled || _day(l.startDate).isAfter(end)) continue;
      final paid = loanPayments
          .where((p) => p.loanId == l.id && !_day(p.date).isAfter(end))
          .fold(0.0, (sum, p) => sum + p.amount);
      final left = l.principal - paid;
      if (left > 0) total -= convert(left, l.currency);
    }
    return total;
  }

  /// A saved snapshot held accounts and bens only. What it left out is added
  /// when it is read, so old days compare fairly with today and nothing
  /// stored needs to change.
  double snapshotTotal(NetWorthSnapshot snapshot) {
    final day = DateTime.tryParse(snapshot.date);
    if (day == null) return snapshot.netWorth;
    return snapshot.netWorth + costAt(_day(day)) + claimsAt(_day(day));
  }
}

bool _counts(Account a) => !a.excludeFromTotal && !a.isGold;

/// Months back from today, newest last, starting at the first month with a
/// record: before it there is nothing to rebuild from.
///
/// The current month is the state of things today, whatever date an entry
/// carries: a salary received early keeps its scheduled date but is already
/// in the balance. Past months walk back from it by undoing later entries.
/// Investments are at cost; nothing here is a market value.
List<NetWorthPoint> netWorthHistory(NetWorthInputs data,
    {required DateTime now, int months = 12}) {
  final today = DateTime(now.year, now.month, now.day);
  final accounts = {
    for (final a in data.accounts)
      if (_counts(a)) a.id: a
  };
  final cashNow = accounts.values
      .fold(0.0, (sum, a) => sum + data.convert(a.balance, a.currency));

  // Signed cash effect of everything that moved a balance.
  final moves = <(DateTime, double)>[];
  for (final t in data.transactions) {
    final m = data.metadata[t.id];
    if (m?.isPending == true || m?.affectsBalance == false) continue;
    final account = accounts[t.accountId];
    if (account == null) continue;
    final currency = t.currency.isEmpty ? account.currency : t.currency;
    final value = data.convert(t.amount, currency);
    moves.add((
      DateTime(t.date.year, t.date.month, t.date.day),
      t.type == 'income' ? value : -value
    ));
  }
  // A goal moves the balance with no transaction behind it.
  for (final c in data._goalMoves) {
    if (!accounts.containsKey(c.accountId)) continue;
    final value = data._goalValue(c);
    moves.add((
      DateTime(c.date.year, c.date.month, c.date.day),
      c.type == 'withdrawal' ? value : -value
    ));
  }

  final operations = data.positions.expand((p) => p.operations).toList();
  var first = today;
  for (final (date, _) in moves) {
    if (date.isBefore(first)) first = date;
  }
  for (final o in operations) {
    final d = NetWorthInputs._localDay(o.date);
    if (d.isBefore(first)) first = d;
  }

  final points = <NetWorthPoint>[];
  for (var back = months - 1; back >= 0; back--) {
    final month = DateTime(today.year, today.month - back);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    if (monthEnd.isBefore(first)) continue;
    final end = back == 0 ? NetWorthInputs.now : monthEnd;
    var cash = cashNow;
    for (final (date, signed) in moves) {
      if (date.isAfter(end)) cash -= signed;
    }
    var income = 0.0;
    for (final o in operations) {
      final d = NetWorthInputs._localDay(o.date);
      if (o.kind == 'income' &&
          d.year == month.year &&
          d.month == month.month) {
        income += o.mainCents / 100;
      }
    }
    points.add(NetWorthPoint(
        month: month,
        cash: cash,
        invested: data.costAt(end),
        others: data.assetsAt(end) + data.claimsAt(end),
        income: income));
  }
  return points;
}
