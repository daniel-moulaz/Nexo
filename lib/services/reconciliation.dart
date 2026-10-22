import '../models/models.dart';
import '../models/transaction_metadata.dart';
import 'finance_rules.dart';

/// A bank movement waiting for review (a row of `notification_suggestions`).
class PendingMovement {
  const PendingMovement(
      {required this.id,
      required this.amountCents,
      required this.description,
      required this.kind,
      required this.occurredAt});
  final String id, description;

  /// expense | income | refund | transfer
  final String kind;
  final int amountCents;
  final DateTime occurredAt;

  factory PendingMovement.fromRow(Map<String, dynamic> r) => PendingMovement(
      id: r['id'] as String,
      amountCents: r['amount_cents'] as int,
      description: r['description'] as String,
      kind: r['kind'] as String,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(r['occurred_at'] as int));

  bool get outgoing => kind == 'expense' || kind == 'transfer';
}

enum Resolution {
  /// Same movement as an entry already in the Nexo: link, create nothing.
  linked,

  /// Possibly an entry already in the Nexo: the person decides.
  maybe,

  /// Money between the person's own accounts (both sides seen).
  ownTransfer,

  /// A payment and its reversal: nothing happened.
  reversal,

  /// Automatic reserve moves (e.g. "Reserva por gasto"): not spending.
  reserve,

  /// Tiny yield credits, below the configured limit.
  smallYield,

  /// Nothing similar in the Nexo: probably not registered yet.
  newEntry,
}

class Match {
  const Match(this.movement, this.resolution,
      {this.transaction, this.score = 0, this.pair, this.categoryId});
  final PendingMovement movement;
  final Resolution resolution;
  final AppTransaction? transaction;

  /// 0..100 for [Resolution.linked] / [Resolution.maybe].
  final int score;

  /// The other side of an own transfer or reversal.
  final PendingMovement? pair;

  /// Category learned from rules or past entries, for new entries.
  final String? categoryId;

  /// Applied without asking (linked, reversal, reserve, small yield).
  bool get automatic =>
      resolution == Resolution.linked ||
      resolution == Resolution.reversal ||
      resolution == Resolution.reserve ||
      resolution == Resolution.smallYield;
}

final _noise = RegExp(
    r'^(ifd\*|ifd |mp \*|mp\*|pg \*|pg\*|pag\*|pp\*|ec \*|dl\*|ebn\*)',
    caseSensitive: false);
final _movementWords = RegExp(
    r'\b(pix|ted|doc|transf\w*|enviad[oa]|recebid[oa]|pagamento|pagto|pgto|com|de|para|do|da|por|compra|no|na|em|cartao|debito|credito|qr|code|ltda|me|eireli|sa)\b');
const _accents = {
  'á': 'a', 'à': 'a', 'â': 'a', 'ã': 'a', 'é': 'e', 'ê': 'e', 'í': 'i', //
  'ó': 'o', 'ô': 'o', 'õ': 'o', 'ú': 'u', 'ü': 'u', 'ç': 'c',
};

/// Merchant / counterparty name without card prefixes (Ifd*, Mp *, Pg *),
/// numbers, CNPJ, punctuation, accents and movement words.
String normalizeMerchant(String text) {
  var s = text.trim().toLowerCase();
  s = s.replaceFirst(_noise, '');
  s = s.split('').map((c) => _accents[c] ?? c).join();
  s = s.replaceAll(RegExp(r'[0-9]'), ' ');
  s = s.replaceAll(RegExp(r'[^a-z ]'), ' ');
  s = s.replaceAll(_movementWords, ' ');
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// token_set_ratio-like similarity, 0..1.
double textSimilarity(String a, String b) {
  final ta = normalizeMerchant(a).split(' ').where((t) => t.length > 1).toSet();
  final tb = normalizeMerchant(b).split(' ').where((t) => t.length > 1).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0;
  final common = ta.intersection(tb).length;
  if (common == 0) {
    // "ifoodcom" vs "ifood": one token contains the other.
    for (final x in ta) {
      for (final y in tb) {
        if (x.length >= 4 &&
            y.length >= 4 &&
            (x.contains(y) || y.contains(x))) {
          return .8;
        }
      }
    }
    return 0;
  }
  return common / (ta.length < tb.length ? ta.length : tb.length);
}

final _reserve = RegExp(r'reserva por gasto|dinheiro retirado|reserva autom',
    caseSensitive: false);
final _yield = RegExp(r'rendimento|remunera[cç][aã]o|juros sobre saldo',
    caseSensitive: false);
final _received = RegExp(r'recebid|pix|ted|transfer', caseSensitive: false);
final _reversalWords =
    RegExp(r'estorno|devolu|cancelad|reembolso', caseSensitive: false);

int _cents(double v) => (v * 100).round();
int _days(DateTime a, DateTime b) => DateTime(a.year, a.month, a.day)
    .difference(DateTime(b.year, b.month, b.day))
    .inDays
    .abs();

/// Decides what each pending movement is, before the person sees it.
///
/// [linkedIds]: entries already tied to a confirmed suggestion (never linked
/// twice). [ownerNames]: how the person's name shows in bank descriptions.
/// [learnedCategory]: category of past entries by normalized merchant.
List<Match> reconcile({
  required List<PendingMovement> pending,
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
  Set<String> linkedIds = const {},
  List<String> ownerNames = const [],
  Set<String> dismissedPairs = const {},
  int smallYieldCents = 100,
  String? Function(PendingMovement)? learnedCategory,
}) {
  final out = <String, Match>{};
  final used = <String>{...linkedIds};
  final owners = [
    for (final n in ownerNames)
      if (normalizeMerchant(n).isNotEmpty) normalizeMerchant(n)
  ];
  bool mentionsOwner(String d) {
    final n = normalizeMerchant(d);
    return owners.any((o) => n.contains(o) || textSimilarity(n, o) >= .99);
  }

  // 1. Reserve moves and tiny yields are never spending or income.
  for (final m in pending) {
    if (_reserve.hasMatch(m.description)) {
      out[m.id] = Match(m, Resolution.reserve);
    } else if (!m.outgoing &&
        _yield.hasMatch(m.description) &&
        m.amountCents < smallYieldCents) {
      out[m.id] = Match(m, Resolution.smallYield);
    }
  }
  List<PendingMovement> open() =>
      pending.where((m) => !out.containsKey(m.id)).toList();

  // 2. Payment and reversal of the same amount, same day.
  for (final paid in open().where((m) => m.outgoing)) {
    if (out.containsKey(paid.id)) continue;
    for (final back in open().where((m) => !m.outgoing)) {
      if (out.containsKey(back.id) ||
          back.amountCents != paid.amountCents ||
          _days(back.occurredAt, paid.occurredAt) > 0) continue;
      // Same merchant giving the money back; a Pix/TED received from the
      // same name is more likely a transfer and is left to step 3.
      final sameName =
          textSimilarity(paid.description, back.description) >= .6 &&
              !_received.hasMatch(back.description) &&
              !mentionsOwner(back.description);
      if (back.kind == 'refund' ||
          _reversalWords.hasMatch(back.description) ||
          sameName) {
        out[paid.id] = Match(paid, Resolution.reversal, pair: back);
        out[back.id] = Match(back, Resolution.reversal, pair: paid);
        break;
      }
    }
  }

  // 3. Own transfers: money out and in, same amount, within a day, both to /
  // from the person (by name) or the same counterparty on both sides.
  for (final out1 in open().where((m) => m.outgoing)) {
    if (out.containsKey(out1.id)) continue;
    for (final in1 in open().where((m) => m.kind == 'income')) {
      if (out.containsKey(in1.id) ||
          in1.amountCents != out1.amountCents ||
          _days(in1.occurredAt, out1.occurredAt) > 1) continue;
      final own =
          (mentionsOwner(out1.description) && mentionsOwner(in1.description)) ||
              (normalizeMerchant(out1.description).isNotEmpty &&
                  textSimilarity(out1.description, in1.description) >= .99);
      if (own) {
        out[out1.id] = Match(out1, Resolution.ownTransfer, pair: in1);
        out[in1.id] = Match(in1, Resolution.ownTransfer, pair: out1);
        break;
      }
    }
  }

  // 4. Entries already in the Nexo.
  final candidates = transactions.where((t) {
    final m = metadata[t.id];
    if (used.contains(t.id) || t.id.startsWith('notification:')) return false;
    // Transfer legs are matched only by own transfers, never as spending.
    return !(m?.source.startsWith('transfer:') ?? false) &&
        m?.source != 'opening_balance';
  }).toList();
  final rest = open();
  int score(PendingMovement m, AppTransaction t, {String? category}) {
    final amount = _cents(t.amount);
    final rel = (amount - m.amountCents).abs() /
        (m.amountCents > 0 ? m.amountCents : 1);
    final days = _days(m.occurredAt, t.date);
    if (rel > .3 || days > 7) return 0;
    var s = 50 * (1 - rel / .3) +
        35 * textSimilarity(m.description, t.description) +
        15 * (1 - days / 7);
    if (category != null && category == t.categoryId) s += 25;
    return s.round().clamp(0, 100);
  }

  bool typeFits(PendingMovement m, AppTransaction t) =>
      m.outgoing ? t.type == 'expense' : t.type == 'income';

  for (final m in rest) {
    final category = learnedCategory?.call(m);
    final options = [
      for (final t in candidates)
        if (typeFits(m, t) && !used.contains(t.id))
          (t, score(m, t, category: category))
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    if (options.isEmpty || options.first.$2 == 0) {
      out[m.id] = Match(m, Resolution.newEntry, categoryId: category);
      continue;
    }
    final (best, s) = options.first;
    final exact = _cents(best.amount) == m.amountCents;
    final days = _days(m.occurredAt, best.date);
    // Unique: no other entry and no other movement with this amount nearby.
    final unique = options
                .where((o) =>
                    _cents(o.$1.amount) == m.amountCents &&
                    _days(o.$1.date, m.occurredAt) <= 1)
                .length ==
            1 &&
        rest
            .where((o) =>
                o.id != m.id &&
                o.amountCents == m.amountCents &&
                o.outgoing == m.outgoing &&
                _days(o.occurredAt, m.occurredAt) <= 1)
            .isEmpty;
    final similar = textSimilarity(m.description, best.description) >= .6;
    if (exact && days <= 3 && (similar || (days <= 1 && unique))) {
      used.add(best.id);
      out[m.id] = Match(m, Resolution.linked,
          transaction: best, score: s < 85 ? 85 : s);
    } else if (s >= 45 && !dismissedPairs.contains('${m.id}|${best.id}')) {
      out[m.id] = Match(m, Resolution.maybe, transaction: best, score: s);
    } else {
      out[m.id] = Match(m, Resolution.newEntry, categoryId: category);
    }
  }
  return [for (final m in pending) out[m.id]!];
}

/// The category most used for this merchant in past entries.
String? Function(PendingMovement) categoryFromHistory(
    List<AppTransaction> transactions,
    Map<String, TransactionMetadata> metadata) {
  final byMerchant = <String, Map<String, int>>{};
  for (final t in transactions) {
    if (FinanceRules.isNeutral(t, metadata[t.id]) || t.categoryId.isEmpty) {
      continue;
    }
    final key = '${t.type}|${normalizeMerchant(t.description)}';
    if (key.endsWith('|')) continue;
    (byMerchant[key] ??= {})
        .update(t.categoryId, (v) => v + 1, ifAbsent: () => 1);
  }
  return (m) {
    final type = m.outgoing ? 'expense' : 'income';
    final counts = byMerchant['$type|${normalizeMerchant(m.description)}'];
    if (counts == null) return null;
    return (counts.entries.toList()..sort((a, b) => b.value - a.value))
        .first
        .key;
  };
}
