import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'finance_rules.dart';
import 'reconciliation.dart' show normalizeMerchant, textSimilarity;

/// A charge that deserves a look: a subscription that came with a different
/// price, the same charge more than once in a few days, or a description
/// that reads like a fee, insurance or service the person may not have asked
/// for. The alert only points; it never concludes nor changes anything.
class ChargeAlert {
  const ChargeAlert.priceChange(this.recurring, this.charges, this.expected)
      : kind = 'price';
  const ChargeAlert.duplicate(this.charges)
      : kind = 'duplicate',
        recurring = null,
        expected = null;
  const ChargeAlert.review(this.charges)
      : kind = 'review',
        recurring = null,
        expected = null;
  final String kind;
  final RecurringPayment? recurring;
  final List<AppTransaction> charges;
  final double? expected;
}

/// Looks at the last [days] days. Installments, transfers, reserves and
/// entries created by the recurring item itself at its own price are fine.
List<ChargeAlert> chargeAlerts({
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  required List<RecurringPayment> recurring,
  required DateTime now,
  Set<String> dismissed = const {},
  int days = 35,
}) {
  final since = DateTime(now.year, now.month, now.day - days);
  final recent = transactions.where((t) {
    final m = metadata[t.id];
    return t.type == 'expense' &&
        !t.date.isBefore(since) &&
        !FinanceRules.isNeutral(t, m) &&
        m?.isPending != true &&
        (m?.installmentTotal ?? 0) <= 1 &&
        !t.id.contains(':installment:');
  }).toList()
    ..sort((a, b) => a.date.compareTo(b.date));
  final out = <ChargeAlert>[];

  // Same merchant and amount, three days apart at most.
  final seen = <String>{};
  for (final t in recent) {
    if (seen.contains(t.id)) continue;
    final merchant = normalizeMerchant(t.description);
    if (merchant.isEmpty) continue;
    final group = [
      for (final o in recent)
        if ((o.amount - t.amount).abs() < .005 &&
            normalizeMerchant(o.description) == merchant &&
            !o.date.isBefore(t.date) &&
            o.date.difference(t.date).inDays <= 3)
          o
    ];
    if (group.length >= 2) {
      seen.addAll(group.map((g) => g.id));
      final key = 'dup:${group.map((g) => g.id).join(',')}';
      if (!dismissed.contains(key)) out.add(ChargeAlert.duplicate(group));
    }
  }

  // A subscription charged with another price.
  for (final r in recurring.where((r) => r.paymentType == 'expense')) {
    final charges = recent
        .where((t) => t.id.startsWith('recurring:${r.id}:')
            ? (t.amount - r.amount).abs() >= .005
            : textSimilarity(t.description, r.name) >= .6)
        .where((t) {
      final diff = (t.amount - r.amount).abs();
      return diff >= 1 && diff >= r.amount * .05;
    }).toList();
    if (charges.isEmpty) continue;
    final key = 'price:${r.id}:${charges.last.id}';
    if (!dismissed.contains(key)) {
      out.add(ChargeAlert.priceChange(r, charges, r.amount));
    }
  }
  // Fees, insurance and services banks add on their own (as the AUVP app
  // does for Itaú, here for any bank), by the description only.
  for (final t in recent) {
    if (!looksLikeBankCharge(t.description)) continue;
    if (!dismissed.contains('review:${t.id}')) out.add(ChargeAlert.review([t]));
  }
  return out;
}

const _bankChargeWords = [
  'seguro',
  'tarifa',
  'anuidade',
  'proteção',
  'protecao',
  'capitalização',
  'capitalizacao',
  'assistência',
  'assistencia',
  'cesta de serviços',
  'cesta de servicos',
  'pacote de serviços',
  'pacote de servicos',
  'encargo',
  'multa',
  'juros',
  'iof',
  'manutenção de conta',
  'manutencao de conta',
  'título de capitalização',
  'titulo de capitalizacao',
];

/// A description that reads like something the bank charged on its own.
bool looksLikeBankCharge(String description) {
  final d = description.toLowerCase();
  return _bankChargeWords.any(d.contains);
}

String chargeAlertKey(ChargeAlert a) => switch (a.kind) {
      'duplicate' => 'dup:${a.charges.map((g) => g.id).join(',')}',
      'review' => 'review:${a.charges.first.id}',
      _ => 'price:${a.recurring!.id}:${a.charges.last.id}',
    };
