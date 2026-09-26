import '../models/models.dart';
import 'transaction_metadata_service.dart';

class FinanceRules {
  static bool isImplicitNeutral(AppTransaction tx) {
    final text = '${tx.description} ${tx.note}'.toLowerCase();
    return text.contains('transfer out') ||
        text.contains('transfer in') ||
        text.contains('transferência') ||
        text.contains('transferencia') ||
        text.contains('entre contas') ||
        text.contains('reserva') ||
        (text.contains('fatura') && text.contains('pagamento')) ||
        text.contains('pagamento da fatura') ||
        text.contains('pagamento de fatura');
  }

  static bool isNeutral(
    AppTransaction tx,
    TransactionMetadata? metadata,
  ) {
    return (metadata?.excludeFromSpending ?? false) || isImplicitNeutral(tx);
  }
}
