import '../models/models.dart';
import 'text_normalize.dart';

/// What the person confirmed before, as a category guess for the next
/// entry with the same description. Local, computed from the ledger, no
/// rules to write. Inspired by Copilot's per-user model: a guess is offered
/// only when the history is clear (at least [minCount] confirmations and
/// [minShare] of them agreeing), and the runner-up stays one tap away.
class CategoryMemory {
  CategoryMemory._(this._counts);

  /// key → (categoryId → count). Keys are normalized descriptions.
  final Map<String, Map<String, int>> _counts;
  final int minCount = 2;
  final double minShare = .6;

  factory CategoryMemory.fromTransactions(Iterable<AppTransaction> items) {
    final counts = <String, Map<String, int>>{};
    for (final t in items) {
      if (t.categoryId.isEmpty) continue;
      final key = keyFor(t.description);
      if (key.isEmpty) continue;
      final byCategory = counts.putIfAbsent('${t.type}:$key', () => {});
      byCategory[t.categoryId] = (byCategory[t.categoryId] ?? 0) + 1;
    }
    return CategoryMemory._(counts);
  }

  static CategoryMemory get empty => CategoryMemory._({});

  /// Lowercase, no accents, digits and punctuation out, spaces collapsed.
  static String keyFor(String description) => normalizeText(description)
      .replaceAll(RegExp(r'[0-9]+'), ' ')
      .replaceAll(RegExp(r'[^a-z ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Category ids ordered by how often they were confirmed for this
  /// description and type, most frequent first.
  List<String> ranked(String description, {required String type}) {
    final byCategory = _counts['$type:${keyFor(description)}'];
    if (byCategory == null) return const [];
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in entries) e.key];
  }

  /// The confident guess, or null when the history is thin or split.
  String? suggest(String description, {required String type}) {
    final byCategory = _counts['$type:${keyFor(description)}'];
    if (byCategory == null || byCategory.isEmpty) return null;
    final total = byCategory.values.fold(0, (s, v) => s + v);
    final best =
        byCategory.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (best.value < minCount || best.value / total < minShare) return null;
    return best.key;
  }
}
