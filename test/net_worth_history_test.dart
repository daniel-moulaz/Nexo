import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/investments/investment_models.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/net_worth_history.dart';

void main() {
  final now = DateTime(2026, 10, 28);
  AppTransaction tx(String id, String type, double v, DateTime d,
          {String account = 'bank'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: v,
          description: id,
          accountId: account,
          categoryId: 'c',
          date: d,
          currency: 'BRL');
  InvestmentOperation op(String id, String kind, int cents, DateTime d) =>
      InvestmentOperation(
          id: id,
          investmentId: 'i',
          kind: kind,
          quantity: 1,
          cents: cents,
          date: d,
          createdAt: d);

  test('cash is rebuilt backwards; investments at cost; income per month', () {
    final points = netWorthHistory(accounts: [
      Account(
          id: 'bank',
          name: 'Banco',
          type: 'bank',
          balance: 1000,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'card',
          name: 'Cartão',
          type: 'credit',
          balance: -300,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'ignored',
          name: 'Fora',
          type: 'bank',
          balance: 999,
          currency: 'BRL',
          colorValue: 0,
          excludeFromTotal: true),
    ], transactions: [
      tx('pay-oct', 'income', 2000, DateTime(2026, 10, 5)),
      tx('rent-oct', 'expense', 800, DateTime(2026, 10, 10)),
      tx('card-oct', 'expense', 300, DateTime(2026, 10, 12), account: 'card'),
      tx('pending', 'expense', 500, DateTime(2026, 10, 15)),
      tx('pay-sep', 'income', 2000, DateTime(2026, 9, 5)),
    ], metadata: {
      'pending': const TransactionMetadata(
          transactionId: 'pending', status: 'pending'),
    }, operations: [
      op('o1', 'buy', 50000, DateTime(2026, 8, 20)),
      op('o2', 'income', 1250, DateTime(2026, 9, 15)),
      op('o3', 'sell', 10000, DateTime(2026, 10, 2)),
    ], convert: (v, _) => v, defaultCurrency: 'BRL', now: now, months: 3);
    expect(points.map((p) => p.month),
        [DateTime(2026, 8), DateTime(2026, 9), DateTime(2026, 10)]);
    // Now: 1000 - 300 = 700 cash. October undone: -2000 +800 +300 → 31/09 = -200.
    expect(points[2].cash, 700);
    expect(points[1].cash, -200);
    // September undone too: -2000 → 31/08 = -2200.
    expect(points[0].cash, -2200);
    expect(points.map((p) => p.invested), [500, 500, 400]);
    expect(points.map((p) => p.income), [0, 12.5, 0]);
    expect(points[2].total, 1100);
  });
}
