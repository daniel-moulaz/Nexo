import '../models/models.dart';
import 'billing_cycle.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

double currentInvoiceRemaining({
  required Account card,
  required DateTime now,
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required List<Map<String, dynamic>> payments,
  required double Function(double, String) convert,
}) {
  final cycle = BillingCycle.forDate(now, card.statementDay, card.dueDay);
  final key = cycle.end.toIso8601String().substring(0, 10);
  var total = 0.0;
  for (final tx in transactions) {
    if (tx.accountId != card.id ||
        tx.date.isBefore(cycle.start) ||
        !tx.date.isBefore(cycle.end.add(const Duration(days: 1)))) continue;
    if (FinanceRules.isNeutral(tx, metadata[tx.id]) &&
        metadata[tx.id]?.source != 'opening_balance') continue;
    total += convert(tx.type == 'income' ? -tx.amount : tx.amount,
        tx.currency.isEmpty ? card.currency : tx.currency);
  }
  for (final payment in payments) {
    if (payment['card_id'] == card.id && payment['cycle_end'] == key) {
      total -= convert((payment['amount'] as num).toDouble(), card.currency);
    }
  }
  return total.clamp(0.0, double.infinity);
}
