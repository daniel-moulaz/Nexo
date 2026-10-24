import 'balance_check.dart';
import 'billing_cycle.dart';

/// The bank's own invoice (Open Finance) for a Nexo invoice, and how far
/// apart they are. The Nexo invoice keeps its closing-day rule; once the bank
/// closes, its total is the final word and the difference points to entries
/// to check. Nothing here creates or moves money.
class OfficialInvoice {
  const OfficialInvoice(this.bill, this.nexoCents);
  final BankBill bill;

  /// Purchases minus credits of the Nexo invoice, in cents.
  final int nexoCents;

  /// Bank minus Nexo: positive when the bank charges more.
  int get differenceCents => bill.totalCents - nexoCents;
  bool get matches => differenceCents.abs() < 1;
}

/// Days a bank date may drift from the Nexo date (weekends, holidays, a
/// closing day the bank moved).
const officialDriftDays = 5;

/// The bank invoice of [cycle]: the closing date when the bank gives one,
/// otherwise the due date. Null when the bank has none (an open invoice,
/// another currency, or a card without Open Finance).
OfficialInvoice? officialFor(BankAccountSnapshot? bank, BillingCycle cycle,
    {required double nexoTotal, required String currency}) {
  if (bank == null || !bank.isCard) return null;
  bool near(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.difference(b).inDays.abs() <= officialDriftDays;
  BankBill? best;
  for (final b in bank.bills) {
    if (b.currency != currency) continue;
    final hit = b.closeDate != null
        ? near(b.closeDate, cycle.end)
        : near(b.dueDate, cycle.due);
    if (!hit) continue;
    // Closest due date wins if two are near (should not happen).
    if (best == null ||
        (cycle.due != null &&
            b.dueDate.difference(cycle.due!).inDays.abs() <
                best.dueDate.difference(cycle.due!).inDays.abs())) {
      best = b;
    }
  }
  return best == null ? null : OfficialInvoice(best, (nexoTotal * 100).round());
}
