import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'finance_rules.dart';

/// A charge that repeats every month and is not registered as recurring yet.
class SubscriptionCandidate {
  const SubscriptionCandidate(
      {required this.key,
      required this.label,
      required this.monthlyAmount,
      required this.months,
      required this.lastDate,
      required this.accountId,
      required this.categoryId});

  /// Normalized description; stable across months ("netflix com").
  final String key;
  final String label;

  /// Most recent amount (subscriptions follow price changes).
  final double monthlyAmount;
  final int months;
  final DateTime lastDate;
  final String accountId, categoryId;
}

/// Finds subscriptions the way Monarch/Copilot do, deterministically: the
/// same merchant charged in at least three different months out of the last
/// six, with a stable amount, still active, and not already recurring.
abstract final class SubscriptionDetector {
  static String normalize(String description) => description
      .toLowerCase()
      .replaceAll(RegExp(r'[0-9]+'), ' ')
      .replaceAll(RegExp(r'[^a-zà-ú ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static List<SubscriptionCandidate> detect({
    required Iterable<AppTransaction> transactions,
    required Map<String, TransactionMetadata> metadata,
    required Iterable<RecurringPayment> recurring,
    required DateTime now,
    required double Function(AppTransaction) amount,
    Set<String> dismissed = const {},
  }) {
    final since = DateTime(now.year, now.month - 5);
    final known = {
      for (final r in recurring) normalize(r.name),
    }..remove('');
    final groups = <String, List<AppTransaction>>{};
    for (final t in transactions) {
      if (t.type != 'expense' ||
          t.date.isBefore(since) ||
          t.date.isAfter(now)) {
        continue;
      }
      final m = metadata[t.id] ?? TransactionMetadata(transactionId: t.id);
      if (FinanceRules.isNeutral(t, m) ||
          m.isPending ||
          m.source == 'recurring' ||
          t.id.startsWith('recurring:') ||
          m.installmentTotal != null) {
        continue;
      }
      final key = normalize(t.description);
      if (key.length < 3) continue;
      groups.putIfAbsent(key, () => []).add(t);
    }
    final result = <SubscriptionCandidate>[];
    for (final e in groups.entries) {
      if (dismissed.contains(e.key) ||
          known.any((k) => k.contains(e.key) || e.key.contains(k))) {
        continue;
      }
      final rows = e.value..sort((a, b) => a.date.compareTo(b.date));
      final months = {for (final t in rows) t.date.year * 12 + t.date.month};
      if (months.length < 3) continue;
      // Several charges in the same month are purchases, not a plan.
      if (rows.length > months.length + 1) continue;
      final values = [for (final t in rows) amount(t)];
      final low = values.reduce((a, b) => a < b ? a : b);
      final high = values.reduce((a, b) => a > b ? a : b);
      if (low <= 0 || high / low > 1.2) continue;
      final last = rows.last;
      if (now.difference(last.date).inDays > 45) continue;
      result.add(SubscriptionCandidate(
          key: e.key,
          label: last.description.trim(),
          monthlyAmount: amount(last),
          months: months.length,
          lastDate: last.date,
          accountId: last.accountId,
          categoryId: last.categoryId));
    }
    result.sort((a, b) => b.monthlyAmount.compareTo(a.monthlyAmount));
    return result;
  }
}
