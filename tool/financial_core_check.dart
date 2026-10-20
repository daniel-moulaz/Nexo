import '../lib/models/models.dart';
import '../lib/models/transaction_metadata.dart';
import '../lib/services/card_commitment.dart';
import '../lib/services/current_invoice_summary.dart';

void main() {
  checkCommitment();
  checkInvoice();
}

void checkCommitment() {
  Account a(String id, String type, double balance,
          {bool excluded = false, String currency = 'BRL'}) =>
      Account(
          id: id,
          name: id,
          type: type,
          balance: balance,
          colorValue: 0,
          currency: currency,
          excludeFromTotal: excluded);
  double convert(double value, String currency) =>
      value * (currency == 'USD' ? 5 : 1);
  void equal(String label, double actual, double expected) {
    if ((actual - expected).abs() > .00001)
      throw StateError('$label: $actual != $expected');
    print('PASS $label');
  }

  final bank = a('bank', 'bank', 2000), card = a('card', 'credit', -600);
  equal('initial available',
      CardCommitment.calculate([bank, card], convert).available, 1400);
  bank.balance -= 200;
  card.balance += 200;
  equal('partial payment no double count',
      CardCommitment.calculate([bank, card], convert).available, 1400);
  bank.balance -= 400;
  card.balance += 400;
  equal('full payment no double count',
      CardCommitment.calculate([bank, card], convert).available, 1400);
  card.balance -= 300;
  equal('new purchase',
      CardCommitment.calculate([bank, card], convert).available, 1100);
  card.balance += 100;
  equal('refund', CardCommitment.calculate([bank, card], convert).available,
      1200);
  final mixed = CardCommitment.calculate([
    a('bank', 'bank', 100),
    a('debt', 'credit', -50, currency: 'USD'),
    a('credit', 'credit', 1000),
    a('gold', 'gold', 999),
    a('excluded', 'credit', -999, excluded: true),
    a('excluded-bank', 'bank', 999, excluded: true)
  ], convert);
  equal('currency and exclusions', mixed.outstanding, 250);
  equal('negative available preserved', mixed.available, -150);
  equal('empty accounts', CardCommitment.calculate([], convert).available, 0);
}

void checkInvoice() {
  final card = Account(
      id: 'card',
      name: 'card',
      type: 'credit',
      balance: -800,
      colorValue: 0,
      currency: 'BRL',
      statementDay: 20,
      dueDay: 27);
  AppTransaction tx(String id, double amount, DateTime date,
          {String type = 'expense', String currency = 'BRL'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: id,
          accountId: 'card',
          categoryId: '',
          date: date,
          currency: currency);
  final transactions = [
    tx('purchase', 600, DateTime(2026, 10, 1)),
    tx('refund', 50, DateTime(2026, 10, 2), type: 'income'),
    tx('payment', 200, DateTime(2026, 10, 3), type: 'income'),
    tx('next', 900, DateTime(2026, 11, 1)),
    tx('prior', 900, DateTime(2026, 9, 1)),
  ];
  final metadata = {
    'payment': const TransactionMetadata(
        transactionId: 'payment',
        excludeFromSpending: true,
        source: 'transfer:payment')
  };
  final payments = <Map<String, dynamic>>[
    {'card_id': 'card', 'cycle_end': '2026-10-20', 'amount': 200},
    {'card_id': 'card', 'cycle_end': '2026-09-20', 'amount': 900},
  ];
  double calculate({DateTime? now}) => currentInvoiceRemaining(
      card: card,
      now: now ?? DateTime(2026, 10, 3),
      transactions: transactions,
      metadata: metadata,
      payments: payments,
      convert: (value, currency) => currency == 'USD' ? value * 5 : value);
  void equal(String label, double actual, double expected) {
    if ((actual - expected).abs() > .00001)
      throw StateError('$label: $actual != $expected');
    print('PASS $label');
  }

  equal('refund and partial payment exactly once', calculate(), 350);
  equal(
      'prior cycle payment isolated', calculate(now: DateTime(2026, 9, 3)), 0);
  equal('future cycle isolated', calculate(now: DateTime(2026, 11, 3)), 900);
  transactions.add(tx('usd', 10, DateTime(2026, 10, 4), currency: 'USD'));
  equal('foreign purchase converted', calculate(), 400);
  transactions.add(tx('opening', 80, DateTime(2026, 10, 4)));
  metadata['opening'] = const TransactionMetadata(
      transactionId: 'opening',
      excludeFromSpending: true,
      source: 'opening_balance');
  equal('opening debt retained', calculate(), 480);
  payments.add({'card_id': 'card', 'cycle_end': '2026-10-20', 'amount': 600});
  equal('overpaid cycle does not become negative debt', calculate(), 0);
  final original = const TransactionMetadata(
      transactionId: 'compat',
      source: 'manual',
      status: 'pending',
      affectsBalance: false,
      installmentCurrent: 2,
      installmentTotal: 4);
  final restored = TransactionMetadata.fromMap(original.toMap());
  if (restored.toMap().toString() != original.toMap().toString()) {
    throw StateError('Metadata round trip changed');
  }
  print('PASS metadata serialization preserved');
}
