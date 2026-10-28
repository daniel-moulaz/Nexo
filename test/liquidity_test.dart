import 'package:nexo/investments/investment_models.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/cash_forecast.dart';
import 'package:nexo/services/cash_timeline.dart';
import 'package:nexo/services/liquidity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Easter and the movable holidays of 2026', () {
    expect(easter(2026), DateTime(2026, 4, 5));
    final h = marketHolidays(2026);
    expect(h, contains(DateTime(2026, 2, 16))); // Carnival Monday
    expect(h, contains(DateTime(2026, 2, 17)));
    expect(h, contains(DateTime(2026, 4, 3))); // Good Friday
    expect(h, contains(DateTime(2026, 6, 4))); // Corpus Christi
    expect(h, contains(DateTime(2026, 11, 2)));
    expect(isBusinessDay(DateTime(2026, 10, 23)), isTrue); // Friday
    expect(isBusinessDay(DateTime(2026, 10, 24)), isFalse); // Saturday
  });

  group('session case 2.10: invoice due Monday 26/10', () {
    const rule = SettlementRule();
    final due = DateTime(2026, 10, 26);

    test('shares sold on Friday arrive on Tuesday: too late', () {
      expect(rule.availableOn('Ações', DateTime(2026, 10, 23, 11)),
          DateTime(2026, 10, 27));
      // Sold on Thursday 22/10, they arrive on Monday 26/10: in time.
      expect(rule.availableOn('Ações', DateTime(2026, 10, 22, 11)),
          DateTime(2026, 10, 26));
      expect(rule.sellBy('Ações', due, DateTime(2026, 10, 22, 9)),
          DateTime(2026, 10, 22));
      expect(rule.sellBy('Ações', due, DateTime(2026, 10, 23, 9)), isNull);
    });

    test('Tesouro before 13:00 the same day; after, the next business day', () {
      expect(rule.availableOn('Renda fixa', DateTime(2026, 10, 23, 12)),
          DateTime(2026, 10, 23));
      expect(rule.availableOn('Renda fixa', DateTime(2026, 10, 23, 14)),
          DateTime(2026, 10, 26));
      expect(rule.sellBy('Renda fixa', due, DateTime(2026, 10, 23, 9)),
          DateTime(2026, 10, 26));
      expect(rule.availableOn('Outros', DateTime(2026, 10, 23)), isNull);
    });

    test('a holiday pushes settlement (Monday 2/11 is Finados)', () {
      expect(rule.availableOn('Ações', DateTime(2026, 10, 29, 11)),
          DateTime(2026, 11, 3));
    });

    test('options by date: R\$ 140 in shares too late on Friday, reserve now',
        () {
      final shares = InvestmentPosition(
          Investment(
              id: 's',
              name: 'Ações',
              assetClass: 'Ações',
              priceMicros: 14 * investmentScale,
              priceAt: DateTime(2026, 10, 22)),
          [
            InvestmentOperation(
                id: 'o',
                investmentId: 's',
                kind: 'opening',
                quantity: 10 * investmentScale,
                cents: 14000,
                date: DateTime(2026, 9, 1),
                createdAt: DateTime(2026, 9, 1))
          ]);
      final options =
          raiseBy(due: due, now: DateTime(2026, 10, 23, 9), positions: [
        shares
      ], goals: [
        SavingsGoal(
            id: 'g',
            name: 'Reserva',
            targetAmount: 500,
            currentAmount: 50,
            currency: 'BRL',
            colorValue: 0)
      ]);
      expect(options.first.kind, 'reserva');
      expect(options.first.inTime, isTrue);
      final s = options.firstWhere((o) => o.kind == 'Ações');
      expect(s.amount, 140);
      expect(s.inTime, isFalse);
      expect(s.availableOn, DateTime(2026, 10, 27));
    });

    test('configurable D+1 if B3 shortens settlement', () {
      expect(
          const SettlementRule(equityDays: 1)
              .availableOn('Ações', DateTime(2026, 10, 23, 11)),
          DateTime(2026, 10, 26));
    });
  });

  test('the invoice that the cash will not cover, and by how much', () {
    final forecast = CashForecast(180, -201.92, [
      ForecastEvent(
          date: DateTime(2026, 10, 26),
          title: 'Fatura Cartão roxo',
          accountId: 'nu',
          kind: 'invoice',
          id: 'nu',
          currency: 'BRL',
          amount: -381.92),
    ], const []);
    final timeline = CashTimeline.build(forecast,
        now: DateTime(2026, 10, 22), days: 30, convert: (v, _) => v);
    final s = shortfalls(timeline);
    expect(s, hasLength(1));
    expect(s.single.event.title, 'Fatura Cartão roxo');
    expect(s.single.missing, closeTo(201.92, 1e-9));
    expect(s.single.balanceAfter, closeTo(-201.92, 1e-9));

    final fine = CashTimeline.build(
        CashForecast(500, 118.08, forecast.events, const []),
        now: DateTime(2026, 10, 22),
        days: 30,
        convert: (v, _) => v);
    expect(shortfalls(fine), isEmpty);
  });
}
