import '../models/models.dart';
import '../models/transaction_metadata.dart';

/// An official card invoice from the bank (Open Finance): totals and dates.
class BankBill {
  const BankBill({
    required this.id,
    required this.dueDate,
    required this.totalCents,
    this.closeDate,
    this.minimumCents,
    this.chargesCents = 0,
    this.paidCents = 0,
    this.currency = 'BRL',
  });
  final String id, currency;
  final DateTime dueDate;
  final DateTime? closeDate;
  final int totalCents, chargesCents, paidCents;
  final int? minimumCents;

  static DateTime? _day(Object? v) {
    final d = v is String ? DateTime.tryParse(v) : null;
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// Null for a row without its essentials (never guessed).
  static BankBill? fromJson(Map<String, dynamic> j) {
    final id = j['bill_id'],
        due = _day(j['due_date']),
        total = j['total_cents'];
    if (id is! String || due == null || total is! num) return null;
    return BankBill(
      id: id,
      dueDate: due,
      closeDate: _day(j['close_date']),
      totalCents: total.toInt(),
      minimumCents: (j['minimum_cents'] as num?)?.toInt(),
      chargesCents: (j['charges_cents'] as num?)?.toInt() ?? 0,
      paidCents: (j['paid_cents'] as num?)?.toInt() ?? 0,
      currency: j['currency'] as String? ?? 'BRL',
    );
  }
}

/// An Open Finance account as the server keeps it (no number, owner or CPF).
class BankAccountSnapshot {
  const BankAccountSnapshot({
    required this.accountId,
    required this.bank,
    required this.type,
    required this.name,
    required this.currency,
    this.balanceCents,
    this.creditLimitCents,
    this.availableCents,
    this.minimumPaymentCents,
    this.closeDate,
    this.dueDate,
    this.nexoAccountId,
    this.bankUpdatedAt,
    this.bills = const [],
  });
  final String accountId, bank, type, name, currency;
  final int? balanceCents,
      creditLimitCents,
      availableCents,
      minimumPaymentCents;
  final DateTime? closeDate, dueDate, bankUpdatedAt;
  final String? nexoAccountId;

  /// Official invoices of a card, newest due date first.
  final List<BankBill> bills;

  bool get isCard => type == 'CREDIT';

  /// What the bank says the account holds, in the Nexo sign convention: a
  /// card is a debt (negative), the whole debt (limit − available) when the
  /// bank gives both, otherwise the open invoice balance.
  int? get nexoSignedCents {
    if (!isCard) return balanceCents;
    final limit = creditLimitCents, available = availableCents;
    if (limit != null && available != null) return -(limit - available);
    final b = balanceCents;
    return b == null ? null : -b;
  }

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory BankAccountSnapshot.fromJson(Map<String, dynamic> j) =>
      BankAccountSnapshot(
        accountId: j['account_id'] as String,
        bank: j['bank'] as String? ?? 'Banco',
        type: j['type'] as String,
        name: j['name'] as String? ?? 'Conta',
        currency: j['currency'] as String? ?? 'BRL',
        balanceCents: (j['balance_cents'] as num?)?.toInt(),
        creditLimitCents: (j['credit_limit_cents'] as num?)?.toInt(),
        availableCents: (j['available_cents'] as num?)?.toInt(),
        minimumPaymentCents: (j['minimum_payment_cents'] as num?)?.toInt(),
        closeDate: _date(j['close_date']),
        dueDate: _date(j['due_date']),
        nexoAccountId: j['nexo_account_id'] as String?,
        bankUpdatedAt: _date(j['bank_updated_at']),
        // Malformed rows are skipped.
        bills: [
          for (final b in j['bills'] as List? ?? const [])
            if (b is Map) BankBill.fromJson(b.cast<String, dynamic>())
        ].whereType<BankBill>().toList(),
      );
}

/// Several bank accounts kept as one Nexo account ("Conta principal" holding
/// every bank): one snapshot with the summed balance, read at the oldest of
/// their times. Null when a balance is missing or the currencies differ.
BankAccountSnapshot? combineBankAccounts(List<BankAccountSnapshot> group) {
  if (group.isEmpty) return null;
  if (group.length == 1) return group.single;
  final currency = group.first.currency;
  var sum = 0;
  DateTime? oldest;
  for (final b in group) {
    final cents = b.nexoSignedCents;
    if (b.isCard || cents == null || b.currency != currency) return null;
    sum += cents;
    final at = b.bankUpdatedAt;
    if (at != null && (oldest == null || at.isBefore(oldest))) oldest = at;
  }
  return BankAccountSnapshot(
    accountId: group.map((b) => b.accountId).join('+'),
    bank: group.map((b) => b.bank).toSet().join(' + '),
    type: 'BANK',
    name: '${group.length} contas',
    currency: currency,
    balanceCents: sum,
    nexoAccountId: group.first.nexoAccountId,
    bankUpdatedAt: oldest,
  );
}

/// The bank balance against the Nexo balance at the same moment.
class BalanceCheck {
  const BalanceCheck(
      {required this.bankCents,
      required this.nexoAtBankCents,
      required this.laterEntries});

  /// Bank balance (Nexo sign convention) when the bank was read.
  final int bankCents;

  /// Nexo balance at that moment: today's balance minus what was entered
  /// for later dates.
  final int nexoAtBankCents;

  /// Entries dated after the bank read (not yet in the bank number).
  final List<AppTransaction> laterEntries;

  int get differenceCents => bankCents - nexoAtBankCents;
  bool get matches => differenceCents.abs() < 1;
}

int _cents(double v) => (v * 100).round();

/// Null when the bank gave no balance or the currencies differ (no guess).
BalanceCheck? checkBalance({
  required Account account,
  required BankAccountSnapshot bank,
  required List<AppTransaction> transactions,
  required Map<String, TransactionMetadata> metadata,
}) {
  final bankCents = bank.nexoSignedCents;
  if (bankCents == null || bank.currency != account.currency) return null;
  final at = bank.bankUpdatedAt;
  var later = 0;
  final laterEntries = <AppTransaction>[];
  if (at != null) {
    for (final t in transactions) {
      if (t.accountId != account.id || !t.date.isAfter(at)) continue;
      final m = metadata[t.id];
      // Same rule as the balance itself: pending entries never moved it.
      if (m?.isPending == true || m?.affectsBalance == false) continue;
      if (t.currency.isNotEmpty && t.currency != account.currency) continue;
      later += t.type == 'income' ? _cents(t.amount) : -_cents(t.amount);
      laterEntries.add(t);
    }
  }
  return BalanceCheck(
      bankCents: bankCents,
      nexoAtBankCents: _cents(account.balance) - later,
      laterEntries: laterEntries);
}
