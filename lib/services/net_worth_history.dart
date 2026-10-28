import '../investments/investment_models.dart';
import '../models/models.dart';
import '../models/transaction_metadata.dart';

/// One month-end of the person's money: cash in accounts, money put into
/// investments (at cost, not at market), and the income those investments
/// paid that month.
class NetWorthPoint {
  const NetWorthPoint(
      {required this.month,
      required this.cash,
      required this.invested,
      required this.income});
  final DateTime month;
  final double cash, invested, income;
  double get total => cash + invested;
}

/// Months back from today, newest last. Cash is rebuilt from the current
/// balances by undoing later entries, so it needs no stored history;
/// investments are summed at cost from their operations. Nothing here is a
/// market value: it is what the person holds and what they put in.
List<NetWorthPoint> netWorthHistory({
  required List<Account> accounts,
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required List<InvestmentOperation> operations,
  required double Function(double amount, String currency) convert,
  required String defaultCurrency,
  required DateTime now,
  int months = 12,
}) {
  final today = DateTime(now.year, now.month, now.day);
  var cashNow = 0.0;
  for (final a in accounts) {
    if (a.excludeFromTotal || a.isGold) continue;
    cashNow += convert(a.balance, a.currency);
  }
  // Signed cash effect of every entry that moved a balance.
  final moves = <(DateTime, double)>[];
  for (final t in transactions) {
    final m = metadata[t.id];
    if (m?.isPending == true || m?.affectsBalance == false) continue;
    final account = accounts.where((a) => a.id == t.accountId).firstOrNull;
    if (account == null || account.excludeFromTotal || account.isGold) continue;
    final currency = t.currency.isEmpty ? account.currency : t.currency;
    final value = convert(t.amount, currency);
    moves.add((
      DateTime(t.date.year, t.date.month, t.date.day),
      t.type == 'income' ? value : -value
    ));
  }
  final points = <NetWorthPoint>[];
  for (var back = months - 1; back >= 0; back--) {
    final month = DateTime(today.year, today.month - back);
    final end = back == 0
        ? today
        : DateTime(month.year, month.month + 1, 0); // last day of month
    var cash = cashNow;
    for (final (date, signed) in moves) {
      if (date.isAfter(end)) cash -= signed;
    }
    var invested = 0.0, income = 0.0;
    for (final o in operations) {
      final d = DateTime(o.date.year, o.date.month, o.date.day);
      if (d.isAfter(end)) continue;
      final value = o.cents / 100;
      switch (o.kind) {
        case 'buy':
        case 'opening':
          invested += value;
        case 'sell':
          invested -= value;
        case 'income':
          if (d.year == month.year && d.month == month.month) income += value;
      }
    }
    points.add(NetWorthPoint(
        month: month,
        cash: cash,
        invested: invested < 0 ? 0 : invested,
        income: income));
  }
  return points;
}
