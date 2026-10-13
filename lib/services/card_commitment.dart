import '../models/models.dart';

/// Balances already include purchases, refunds and invoice payments.
/// Never subtract payment records again or offset one card with another's credit.
class CardCommitment {
  final double cash, outstanding;
  double get available => cash - outstanding;
  const CardCommitment(this.cash, this.outstanding);

  static CardCommitment calculate(
      List<Account> accounts, double Function(double, String) convert) {
    double cash = 0, outstanding = 0;
    for (final account in accounts) {
      if (account.excludeFromTotal || account.isGold) continue;
      if (account.type == 'credit') {
        outstanding += convert(
            (-account.balance).clamp(0.0, double.infinity), account.currency);
      } else {
        cash += convert(account.balance, account.currency);
      }
    }
    return CardCommitment(cash, outstanding);
  }
}
