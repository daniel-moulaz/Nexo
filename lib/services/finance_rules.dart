import '../models/models.dart';
import '../models/transaction_metadata.dart';

class FinanceRules {
  static bool isImplicitNeutral(AppTransaction tx) {
    final text = '${tx.description} ${tx.note}'.toLowerCase();
    return text.contains('transfer out') ||
        text.contains('transfer in') ||
        text.startsWith('transferência enviada') ||
        text.startsWith('transferência recebida') ||
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
