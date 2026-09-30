import '../models/models.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

class EntryDefaults {
  static Account? recentAccount(
      List<Account> accounts,
      List<AppTransaction> transactions,
      Map<String, TransactionMetadata> metadata,
      String type) {
    final recent = transactions
        .where((t) =>
            t.type == type &&
            (metadata[t.id]?.source ?? 'manual') == 'manual' &&
            metadata[t.id]?.isPending != true &&
            !FinanceRules.isNeutral(t, metadata[t.id]))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    for (final tx in recent) {
      final account =
          accounts.where((a) => a.id == tx.accountId && !a.isGold).firstOrNull;
      if (account != null) return account;
    }
    return null;
  }
}
