import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/subscription_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 10, 21);
  var n = 0;
  AppTransaction tx(String description, double amount, DateTime date,
          {String type = 'expense'}) =>
      AppTransaction(
          id: 't${n++}',
          type: type,
          amount: amount,
          description: description,
          accountId: 'card',
          categoryId: 'entertainment',
          date: date);

  List<SubscriptionCandidate> detect(List<AppTransaction> rows,
          {Map<String, TransactionMetadata> meta = const {},
          List<RecurringPayment> recurring = const [],
          Set<String> dismissed = const {}}) =>
      SubscriptionDetector.detect(
          transactions: rows,
          metadata: meta,
          recurring: recurring,
          now: now,
          amount: (t) => t.amount,
          dismissed: dismissed);

  List<AppTransaction> monthly(String name, List<double> values) => [
        for (var i = 0; i < values.length; i++)
          tx(name, values[i], DateTime(2026, 10 - (values.length - 1 - i), 5))
      ];

  test('a stable monthly charge is a subscription, with the latest price', () {
    final found = detect(monthly('NETFLIX.COM 0423', [39.9, 39.9, 44.9]));
    expect(found.single.key, 'netflix com');
    expect(found.single.monthlyAmount, 44.9);
    expect(found.single.months, 3);
  });

  test('purchases, varying amounts and old habits are not subscriptions', () {
    // Market every week: several charges per month.
    final market = [
      for (var m = 8; m <= 10; m++)
        for (final d in [3, 10, 17])
          tx('Mercado Bom', 120, DateTime(2026, m, d))
    ];
    expect(detect(market), isEmpty);
    expect(detect(monthly('Uber', [12, 48, 25])), isEmpty, reason: 'varies');
    expect(detect(monthly('Spotify', [21.9, 21.9])), isEmpty,
        reason: 'two months are not enough');
    final stopped = [
      for (var m = 3; m <= 6; m++) tx('Academia X', 99, DateTime(2026, m, 5))
    ];
    expect(detect(stopped), isEmpty, reason: 'no charge in the last 45 days');
  });

  test('already recurring, dismissed, pending or installments are left out',
      () {
    final rows = monthly('Disney Plus', [33.9, 33.9, 33.9]);
    expect(
        detect(rows, recurring: [
          RecurringPayment(
              id: 'r',
              name: 'Disney Plus',
              accountId: 'card',
              categoryId: 'entertainment',
              amount: 33.9,
              freqVal: 1,
              freqUnit: 'months',
              startDate: DateTime(2026, 8, 5),
              nextDate: DateTime(2026, 11, 5))
        ]),
        isEmpty);
    expect(detect(rows, dismissed: {'disney plus'}), isEmpty);
    final installments = {
      for (final t in rows)
        t.id: TransactionMetadata(
            transactionId: t.id, installmentCurrent: 1, installmentTotal: 10)
    };
    expect(detect(rows, meta: installments), isEmpty);
    final income = monthly('Aluguel recebido', [1000, 1000, 1000])
        .map((t) => tx(t.description, t.amount, t.date, type: 'income'))
        .toList();
    expect(detect(income), isEmpty);
  });
}
