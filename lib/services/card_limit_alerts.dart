import '../models/models.dart';

/// A recurring charge that will not fit in what is left of a card's limit.
class CardLimitAlert {
  const CardLimitAlert(
      {required this.card,
      required this.charge,
      required this.date,
      required this.amount,
      required this.free});
  final Account card;
  final RecurringPayment charge;
  final DateTime date;
  final double amount;

  /// What the limit will have left when this charge arrives.
  final double free;
  double get short => amount - free;
}

/// Walks each card's recurring charges in date order, within [days], taking
/// them from the limit left today. Purchases yet to come are unknown, so a
/// missing alert promises nothing. Only the first charge that does not fit
/// is reported: the ones after it depend on what the person does about it.
List<CardLimitAlert> cardLimitAlerts({
  required List<Account> accounts,
  required List<RecurringPayment> recurring,
  required DateTime now,
  int days = 30,
}) {
  final until = DateTime(now.year, now.month, now.day + days, 23, 59);
  final out = <CardLimitAlert>[];
  for (final card in accounts) {
    final limit = card.creditLimit;
    if (card.type != 'credit' || limit == null || limit <= 0) continue;
    final charges = recurring
        .where((r) =>
            r.accountId == card.id &&
            r.paymentType != 'income' &&
            r.canComplete &&
            !r.nextActionDate.isAfter(until))
        .toList()
      ..sort((a, b) => a.nextActionDate.compareTo(b.nextActionDate));
    var free = limit - (card.balance < 0 ? -card.balance : 0);
    for (final r in charges) {
      if (r.nextActionAmount > free + .005) {
        out.add(CardLimitAlert(
            card: card,
            charge: r,
            date: r.nextActionDate,
            amount: r.nextActionAmount,
            free: free < 0 ? 0 : free));
        break;
      }
      free -= r.nextActionAmount;
    }
  }
  return out;
}
