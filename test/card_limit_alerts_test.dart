import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/card_limit_alerts.dart';

void main() {
  final now = DateTime(2026, 11, 6);
  Account card({double balance = -640, double? limit = 650}) => Account(
      id: 'card',
      name: 'Cartão fictício',
      type: 'credit',
      balance: balance,
      currency: 'BRL',
      colorValue: 0,
      statementDay: 19,
      dueDay: 26,
      creditLimit: limit);
  RecurringPayment charge(String id, double amount, DateTime next,
          {String account = 'card', String type = 'expense', DateTime? end}) =>
      RecurringPayment(
          id: id,
          name: id,
          accountId: account,
          categoryId: 'c',
          amount: amount,
          paymentType: type,
          freqVal: 1,
          freqUnit: 'months',
          startDate: DateTime(2026, 1, 1),
          nextDate: next,
          endDate: end);

  test('a charge that does not fit what is left is reported', () {
    final alerts = cardLimitAlerts(
        accounts: [card()],
        recurring: [charge('Assinatura', 120, DateTime(2026, 11, 14))],
        now: now);
    expect(alerts.single.charge.name, 'Assinatura');
    expect(alerts.single.free, closeTo(10, .001));
    expect(alerts.single.short, closeTo(110, .001));
  });

  test('charges add up: the second one is what no longer fits', () {
    final alerts = cardLimitAlerts(accounts: [
      card(balance: -500)
    ], recurring: [
      charge('depois', 100, DateTime(2026, 11, 20)),
      charge('antes', 100, DateTime(2026, 11, 10)),
    ], now: now);
    expect(alerts.single.charge.name, 'depois');
    expect(alerts.single.free, closeTo(50, .001));
  });

  test('only what can reach the limit counts', () {
    expect(
        cardLimitAlerts(accounts: [
          card()
        ], recurring: [
          charge('longe', 120, DateTime(2026, 12, 20)),
          charge('outra conta', 120, DateTime(2026, 11, 14), account: 'bank'),
          charge('renda', 120, DateTime(2026, 11, 14), type: 'income'),
          charge('acabou', 120, DateTime(2026, 11, 14),
              end: DateTime(2026, 10, 1)),
        ], now: now),
        isEmpty);
  });

  test('a card without a limit, or with room, says nothing', () {
    expect(
        cardLimitAlerts(
            accounts: [card(limit: null)],
            recurring: [charge('a', 120, DateTime(2026, 11, 14))],
            now: now),
        isEmpty);
    expect(
        cardLimitAlerts(
            accounts: [card(balance: 0)],
            recurring: [charge('a', 120, DateTime(2026, 11, 14))],
            now: now),
        isEmpty);
  });

  test('a card over its limit has nothing left, not a negative amount', () {
    final alert = cardLimitAlerts(
            accounts: [card(balance: -700)],
            recurring: [charge('a', 10, DateTime(2026, 11, 14))],
            now: now)
        .single;
    expect(alert.free, 0);
    expect(alert.short, 10);
  });
}
