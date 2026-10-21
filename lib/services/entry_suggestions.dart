import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'finance_rules.dart';

/// Past entries whose description matches what is being typed: one per
/// description (the most recent), those starting with the text first.
/// Transfers, reserves and investment movements are left out, so picking
/// one never copies a neutral classification into a new expense.
List<AppTransaction> similarEntries(Iterable<AppTransaction> transactions,
    Map<String, TransactionMetadata> metadata, String query, String type,
    {int max = 4}) {
  final q = query.trim().toLowerCase();
  if (q.length < 2) return const [];
  final latest = <String, AppTransaction>{};
  for (final t in transactions) {
    final key = t.description.trim().toLowerCase();
    if (t.type != type ||
        key.isEmpty ||
        key == q ||
        !key.contains(q) ||
        t.id.startsWith('investment:') ||
        FinanceRules.isNeutral(t, metadata[t.id])) {
      continue;
    }
    final seen = latest[key];
    if (seen == null || t.date.isAfter(seen.date)) latest[key] = t;
  }
  final out = latest.values.toList()
    ..sort((a, b) {
      final sa = a.description.toLowerCase().startsWith(q) ? 0 : 1;
      final sb = b.description.toLowerCase().startsWith(q) ? 0 : 1;
      return sa != sb ? sa - sb : b.date.compareTo(a.date);
    });
  return out.take(max).toList();
}
