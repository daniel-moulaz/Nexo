import 'package:expensy/services/current_invoice_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/services/card_commitment.dart';
import 'package:expensy/services/transaction_metadata_service.dart';

void main() {
  Account account(String id, String type, double balance,
          {bool excluded = false, String currency = 'BRL'}) =>
      Account(
          id: id,
          name: id,
          type: type,
          balance: balance,
          colorValue: 0,
          currency: currency,
          excludeFromTotal: excluded,
          statementDay: 20,
          dueDay: 27);
  double convert(double amount, String currency) =>
      amount * (currency == 'USD' ? 5 : 1);

  test(
      'Partial/full invoice payment preserves available cash without double counting',
      () {
    final bank = account('bank', 'bank', 2000);
    final card = account('card', 'credit', -600);
    expect(CardCommitment.calculate([bank, card], convert).available, 1400);
    bank.balance -= 200;
    card.balance += 200;
    final partial = CardCommitment.calculate([bank, card], convert);
    expect(partial.cash, 1800);
    expect(partial.outstanding, 400);
    expect(partial.available, 1400);
    bank.balance -= 400;
    card.balance += 400;
    expect(CardCommitment.calculate([bank, card], convert).available, 1400);
  });
  test(
      'Positive credit is not spendable cash; exclusions and currency are respected',
      () {
    final result = CardCommitment.calculate([
      account('bank', 'bank', 100),
      account('debt', 'credit', -50, currency: 'USD'),
      account('credit', 'credit', 1000),
      account('gold', 'gold', 999),
      account('excluded', 'credit', -999, excluded: true),
      account('excluded-bank', 'bank', 999, excluded: true),
    ], convert);
    expect(result.cash, 100);
    expect(result.outstanding, 250);
    expect(result.available, -150);
  });
  test('Current cycle includes refunds and partial payments exactly once', () {
    final card = account('card', 'credit', -400);
    AppTransaction tx(String id, double amount, DateTime date,
            {String type = 'expense'}) =>
        AppTransaction(
            id: id,
            type: type,
            amount: amount,
            description: id,
            accountId: 'card',
            categoryId: '',
            date: date,
            currency: 'BRL');
    final remaining = currentInvoiceRemaining(
        card: card,
        now: DateTime(2026, 10, 3),
        transactions: [
          tx('purchase', 600, DateTime(2026, 10, 1)),
          tx('refund', 50, DateTime(2026, 10, 2), type: 'income'),
          tx('payment', 200, DateTime(2026, 10, 3), type: 'income'),
          tx('future', 900, DateTime(2026, 11, 1)),
          tx('previous', 900, DateTime(2026, 9, 1))
        ],
        metadata: {
          'payment': const TransactionMetadata(
              transactionId: 'payment',
              excludeFromSpending: true,
              source: 'transfer:payment')
        },
        payments: [
          {'card_id': 'card', 'cycle_end': '2026-10-20', 'amount': 200},
          {'card_id': 'card', 'cycle_end': '2026-09-20', 'amount': 999}
        ],
        convert: convert);
    expect(remaining, 350);
  });
}
