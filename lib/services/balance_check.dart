import '../models/models.dart';
import '../models/transaction_metadata.dart';

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
  });
  final String accountId, bank, type, name, currency;
  final int? balanceCents,
      creditLimitCents,
      availableCents,
      minimumPaymentCents;
  final DateTime? closeDate, dueDate, bankUpdatedAt;
  final String? nexoAccountId;

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
