import 'package:expensy/models/models.dart';
import 'package:expensy/models/transaction_metadata.dart';
import 'package:expensy/services/charge_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 21);
  AppTransaction tx(String id, double amount, String description, int day) =>
      AppTransaction(
          id: id,
          type: 'expense',
          amount: amount,
          description: description,
          accountId: 'card',
          categoryId: 'c',
          date: DateTime(2026, 10, day, 12));
  final spotify = RecurringPayment(
      id: 'spotify',
      name: 'Spotify',
      accountId: 'card',
      categoryId: 'c',
      amount: 6.82,
      freqVal: 1,
      freqUnit: 'months',
      startDate: DateTime(2026, 1, 15),
      nextDate: DateTime(2026, 11, 15));

  test('three bike charges in three days and a subscription price change', () {
    final alerts = chargeAlerts(transactions: [
      tx('t1', 32.90, 'Tembici', 10),
      tx('t2', 32.90, 'TEMBICI*', 11),
      tx('t3', 32.90, 'Tembici', 12),
      tx('s', 40.90, 'Spotify', 15),
      // Fine: different amounts, an installment and a transfer.
      tx('m1', 20, 'Mercado', 3),
      tx('m2', 25, 'Mercado', 4),
      tx('p1', 100, 'Loja', 5),
      tx('p2', 100, 'Loja', 5),
      tx('x1', 50, 'Transferência enviada', 6),
      tx('x2', 50, 'Transferência enviada', 6),
    ], metadata: {
      'p1': const TransactionMetadata(
          transactionId: 'p1', installmentCurrent: 1, installmentTotal: 3),
      'p2': const TransactionMetadata(
          transactionId: 'p2', installmentCurrent: 2, installmentTotal: 3),
      'x1': const TransactionMetadata(
          transactionId: 'x1',
          excludeFromSpending: true,
          source: 'transfer:x1'),
      'x2': const TransactionMetadata(
          transactionId: 'x2',
          excludeFromSpending: true,
          source: 'transfer:x2'),
    }, recurring: [
      spotify
    ], now: now);
    final dup = alerts.where((a) => a.kind == 'duplicate').toList();
    expect(dup, hasLength(1));
    expect(dup.single.charges.map((t) => t.id), ['t1', 't2', 't3']);
    final price = alerts.where((a) => a.kind == 'price').single;
    expect(price.recurring!.id, 'spotify');
    expect(price.charges.single.amount, 40.90);
    expect(price.expected, 6.82);

    final quiet = chargeAlerts(
        transactions: [
          tx('t1', 32.90, 'Tembici', 10),
          tx('t2', 32.90, 'Tembici', 11),
          tx('s', 40.90, 'Spotify', 15),
        ],
        metadata: const {},
        recurring: [
          spotify
        ],
        now: now,
        dismissed: alerts.map(chargeAlertKey).toSet()..add('dup:t1,t2'));
    expect(quiet, isEmpty, reason: 'dismissed alerts stay quiet');
  });

  test('a charge at the expected price is not an alert', () {
    expect(
        chargeAlerts(
            transactions: [tx('s', 6.82, 'Spotify', 15)],
            metadata: const {},
            recurring: [spotify],
            now: now),
        isEmpty);
  });

  test('a fee, insurance or service by its description is "para conferir"', () {
    final alerts = chargeAlerts(transactions: [
      tx('fee', 12.9, 'Tarifa pacote de serviços', 3),
      tx('ins', 29.9, 'SEGURO CARTAO PROTEGIDO', 5),
      tx('food', 23, 'Mercado da esquina', 6),
    ], metadata: const {}, recurring: const [], now: now);
    expect(alerts.map((a) => a.kind), ['review', 'review']);
    expect(alerts.map((a) => a.charges.single.id), ['fee', 'ins']);
    expect(chargeAlertKey(alerts.first), 'review:fee');
    final later = chargeAlerts(
        transactions: [
          tx('fee', 12.9, 'Tarifa pacote de serviços', 3),
        ],
        metadata: const {},
        recurring: const [],
        now: now,
        dismissed: {'review:fee'});
    expect(later, isEmpty, reason: 'recognized once, never asked again');
    expect(looksLikeBankCharge('Anuidade diferencial'), isTrue);
    expect(looksLikeBankCharge('Almoço'), isFalse);
  });
}
