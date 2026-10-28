import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'finance_rules.dart';
import 'text_normalize.dart';

/// Where the money went, by place: entries grouped by their description
/// (numbers and punctuation ignored), biggest first.
class MerchantLine {
  const MerchantLine(
      {required this.name,
      required this.total,
      required this.count,
      required this.categoryId});
  final String name;
  final double total;
  final int count;

  /// The category most used for this place.
  final String categoryId;
}

List<MerchantLine> merchantBreakdown({
  required Iterable<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required DateTime from,
  required DateTime to, // exclusive
  required double Function(AppTransaction) amount,
  int take = 8,
}) {
  final totals = <String, double>{};
  final counts = <String, int>{};
  final names = <String, String>{};
  final categories = <String, Map<String, int>>{};
  for (final t in transactions) {
    if (t.type != 'expense') continue;
    if (t.date.isBefore(from) || !t.date.isBefore(to)) continue;
    final m = metadata[t.id];
    if (FinanceRules.isNeutral(t, m) || m?.isPending == true) continue;
    final key = normalizeText(t.description)
        .replaceAll(RegExp(r'[0-9]+'), ' ')
        .replaceAll(RegExp(r'[^a-z ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (key.isEmpty) continue;
    totals[key] = (totals[key] ?? 0) + amount(t);
    counts[key] = (counts[key] ?? 0) + 1;
    names.putIfAbsent(key, () => t.description.trim());
    final byCat = categories.putIfAbsent(key, () => {});
    byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + 1;
  }
  final lines = [
    for (final e in totals.entries)
      MerchantLine(
          name: names[e.key]!,
          total: e.value,
          count: counts[e.key]!,
          categoryId: categories[e.key]!
              .entries
              .reduce((a, b) => a.value >= b.value ? a : b)
              .key)
  ]..sort((a, b) => b.total.compareTo(a.total));
  return lines.take(take).toList();
}
