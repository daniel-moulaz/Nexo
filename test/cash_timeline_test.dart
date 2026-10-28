import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/services/cash_forecast.dart';
import 'package:nexo/services/cash_timeline.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/transaction_metadata_service.dart';

void main() {
  final now = DateTime(2026, 10, 13, 16);
  ForecastEvent event(int day, double amount, {String currency = 'BRL'}) =>
      ForecastEvent(
          date: DateTime(2026, 10, day, 23, 59),
          title: 'Teste',
          accountId: 'bank',
          kind: 'transaction',
          id: '$day:$amount',
          currency: currency,
          amount: amount);
  CashTimeline timeline(List<ForecastEvent> events, {int days = 7}) =>
      CashTimeline.build(CashForecast(1000, 0, events, []),
          now: now, days: days, convert: (v, c) => v * (c == 'USD' ? 5 : 1));

  test('Overdue is applied once today; cutoff includes entire last day', () {
    final t = timeline(
        [event(12, -80), event(13, -20), event(20, -100), event(21, -999)]);
    expect(t.points.first.balance, 1000);
    expect(t.points[1].balance, 900);
    expect(t.points.last.balance, 800);
    expect(t.outflow, 200);
    expect(t.overdue, hasLength(1));
    expect(t.upcoming, hasLength(2));
    expect(t.points.last.date, DateTime(2026, 10, 20));
  });
  test('Shows cash shortage before salary even if final balance is positive',
      () {
    final t = timeline([event(18, 1500), event(15, -1200)]);
    expect(t.lowest.balance, -200);
    expect(t.lowest.date, DateTime(2026, 10, 15));
    expect(t.points.last.balance, 1300);
    expect(t.inflow, 1500);
    expect(t.upcoming.first.date.day, 15);
  });
  test(
      'Zero informational events do not look like bills; currency converts once',
      () {
    final t = timeline([event(15, 0), event(16, -10, currency: 'USD')]);
    expect(t.upcoming, hasLength(1));
    expect(t.outflow, 50);
    expect(t.points.last.balance, 950);
  });
  test(
      'Empty and today-only forecast keep current balance without fabricated events',
      () {
    final t = timeline([], days: 0);
    expect(t.points.map((p) => p.balance), [1000, 1000]);
    expect(t.overdue, isEmpty);
    expect(t.upcoming, isEmpty);
    expect(() => t.points.clear(), throwsUnsupportedError);
    expect(() => timeline([], days: 367), throwsArgumentError);
    expect(() => timeline([], days: -1), throwsArgumentError);
  });
  test(
      'Card payment is cash once, transfer is neutral, pending not deducted now',
      () {
    final bank = Account(
        id: 'bank',
        name: 'Banco',
        type: 'bank',
        balance: 2200,
        currency: 'BRL',
        colorValue: 0);
    final reserve = Account(
        id: 'reserve',
        name: 'Reserva',
        type: 'bank',
        balance: 200,
        currency: 'BRL',
        colorValue: 0);
    final card = Account(
        id: 'card',
        name: 'Cartão',
        type: 'credit',
        balance: -120,
        currency: 'BRL',
        colorValue: 0,
        statementDay: 20,
        dueDay: 27);
    AppTransaction tx(String id, String account, String type, double value) =>
        AppTransaction(
            id: id,
            description: id,
            accountId: account,
            type: type,
            amount: value,
            categoryId: 'food',
            date: now,
            currency: 'BRL');
    final forecast = CashForecast.calculate(
        now: now,
        until: DateTime(2026, 11, 12),
        accounts: [bank, reserve, card],
        transactions: [
          tx('out', 'bank', 'expense', 200),
          tx('in', 'reserve', 'income', 200),
          tx('purchase', 'card', 'expense', 120),
          tx('internet', 'bank', 'expense', 80)
        ],
        metadata: {
          'out': const TransactionMetadata(
              transactionId: 'out',
              excludeFromSpending: true,
              source: 'transfer:test'),
          'in': const TransactionMetadata(
              transactionId: 'in',
              excludeFromSpending: true,
              source: 'transfer:test'),
          'internet': TransactionMetadata(
              transactionId: 'internet',
              status: 'pending',
              dueDate: DateTime(2026, 10, 18)),
        },
        recurring: [],
        invoicePayments: [],
        convert: (v, _) => v);
    final t =
        CashTimeline.build(forecast, now: now, days: 30, convert: (v, _) => v);
    expect(t.points.first.balance, 2400);
    expect(t.points.last.balance, 2200);
    expect(t.points.last.balance, forecast.projected);
    expect(t.outflow, 200);
    expect(bank.balance, 2200);
    expect(card.balance, -120);
  });
}
