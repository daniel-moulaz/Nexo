import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/investments/investment_models.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/net_worth_history.dart';

void main() {
  final now = DateTime(2026, 11, 6);
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
  Account account(String id, String type, double balance,
          {bool excluded = false}) =>
      Account(
          id: id,
          name: id,
          type: type,
          balance: balance,
          currency: 'BRL',
          colorValue: 0,
          excludeFromTotal: excluded);
  Investment stock(String id, {int priceCents = 1000}) => Investment(
      id: id,
      name: id,
      assetClass: 'Ações',
      ticker: 'TEST3',
      institution: '',
      priceMicros: priceCents * 10000,
      priceAt: now,
      priceSource: 'manual');
  InvestmentOperation op(
          String id, String asset, String kind, int qty, int cents, DateTime d,
          {String? cash}) =>
      InvestmentOperation(
          id: id,
          investmentId: asset,
          kind: kind,
          quantity: qty * investmentScale,
          cents: cents,
          date: d,
          createdAt: d,
          cashAccountId: cash);
  double same(double v, String _) => v;
  List<double> totals(List<NetWorthPoint> points) =>
      points.map((p) => double.parse(p.total.toStringAsFixed(2))).toList();

  group('accounts, a card and shares bought in September and October', () {
    // Started with 700 in the bank. Salary of 1000 for 07/11 came in early,
    // on the 6th: it is in the balance and keeps its scheduled date.
    final data = NetWorthInputs(
      accounts: [
        account('bank', 'bank', 1200),
        account('card', 'credit', -300)
      ],
      transactions: [
        tx('card-sep', 'expense', 100, DateTime(2026, 9, 25), account: 'card'),
        tx('buy-sep', 'expense', 200, DateTime(2026, 9, 28)),
        tx('card-oct', 'expense', 400, DateTime(2026, 10, 10), account: 'card'),
        tx('buy-oct', 'expense', 100, DateTime(2026, 10, 15)),
        // Paying the invoice is a transfer: one leg on each side.
        tx('pay-out', 'expense', 200, DateTime(2026, 10, 20)),
        tx('pay-in', 'income', 200, DateTime(2026, 10, 20), account: 'card'),
        tx('salary', 'income', 1000, DateTime(2026, 11, 7)),
      ],
      metadata: const {},
      positions: [
        InvestmentPosition(stock('A', priceCents: 3000), [
          op('a1', 'A', 'buy', 10, 20000, DateTime(2026, 9, 28), cash: 'bank'),
          op('a2', 'A', 'buy', 5, 10000, DateTime(2026, 10, 15), cash: 'bank'),
        ]),
      ],
      convert: same,
    );
    final points = netWorthHistory(data, now: now, months: 6);

    test('starts at the first record, not before', () {
      expect(points.map((p) => p.month),
          [DateTime(2026, 9), DateTime(2026, 10), DateTime(2026, 11)]);
    });

    test('month by month, card debt included', () {
      // Sep: bank 500, card -100. Oct: bank 200, card -300. Today: 1200, -300.
      expect(points.map((p) => p.cash), [400, -100, 900]);
      expect(points.map((p) => p.invested), [200, 300, 300]);
      expect(totals(points), [600, 200, 1200]);
    });

    test('a salary received early is not taken off today', () {
      expect(points.last.cash, 900);
    });

    test('today differs from market only by what the shares gained', () {
      expect(data.marketValue, 450);
      expect(points.last.total + data.marketValue - points.last.invested,
          900 + 450);
    });
  });

  test('buying shares leaves net worth where it was', () {
    final before = netWorthHistory(
        NetWorthInputs(
            accounts: [account('bank', 'bank', 1000)],
            transactions: [tx('in', 'income', 1000, DateTime(2026, 10, 1))],
            metadata: const {},
            positions: const [],
            convert: same),
        now: now);
    final after = netWorthHistory(
        NetWorthInputs(accounts: [
          account('bank', 'bank', 700)
        ], transactions: [
          tx('in', 'income', 1000, DateTime(2026, 10, 1)),
          tx('buy', 'expense', 300, DateTime(2026, 11, 3)),
        ], metadata: const {}, positions: [
          InvestmentPosition(stock('A'), [
            op('o', 'A', 'buy', 3, 30000, DateTime(2026, 11, 3), cash: 'bank')
          ])
        ], convert: same),
        now: now);
    expect(after.last.total, before.last.total);
  });

  test('a sale takes out what the shares cost, not what they sold for', () {
    final data = NetWorthInputs(accounts: [
      account('bank', 'bank', 0)
    ], transactions: const [], metadata: const {}, positions: [
      InvestmentPosition(stock('A'), [
        op('b', 'A', 'buy', 4, 40000, DateTime(2026, 10, 1)),
        op('s', 'A', 'sell', 2, 15000, DateTime(2026, 10, 20)),
      ])
    ], convert: same);
    expect(data.costAt(DateTime(2026, 10, 10)), 400);
    expect(data.costAt(DateTime(2026, 10, 31)), 200);
  });

  test('a goal keeps the money in net worth; bookkeeping adds nothing', () {
    SavingsContribution move(String id, String type, double v, DateTime d,
            {String account = 'bank'}) =>
        SavingsContribution(
            id: id,
            goalId: 'g',
            amount: v,
            accountId: account,
            type: type,
            date: d);
    final data = NetWorthInputs(accounts: [
      account('bank', 'bank', 700)
    ], transactions: [
      tx('in', 'income', 1000, DateTime(2026, 9, 1))
    ], metadata: const {}, positions: const [], contributions: [
      move('in', 'contribution', 400, DateTime(2026, 10, 5)),
      move('out', 'withdrawal', 100, DateTime(2026, 11, 2)),
      move('note', 'contribution', 999, DateTime(2026, 10, 6), account: ''),
    ], convert: same);
    final points = netWorthHistory(data, now: now, months: 3);
    expect(points.map((p) => p.cash), [1000, 600, 700]);
    expect(points.map((p) => p.others), [0, 400, 300]);
    expect(totals(points), [1000, 1000, 1000]);
  });

  test('debts and money lent count, a settled one does not', () {
    final loan = Loan(
        id: 'l',
        name: 'l',
        principal: 1000,
        currency: 'BRL',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2027, 9, 1));
    final data = NetWorthInputs(accounts: [
      account('bank', 'bank', 2000)
    ], transactions: [
      tx('in', 'income', 1000, DateTime(2026, 9, 1))
    ], metadata: const {}, positions: const [], loans: [
      loan
    ], loanPayments: [
      LoanPayment(
          id: 'p',
          loanId: 'l',
          date: DateTime(2026, 10, 10),
          amount: 300,
          currency: 'BRL')
    ], lended: [
      LendedMoney(
          id: 'open',
          personId: 'x',
          amount: 50,
          type: 'lent',
          date: DateTime(2026, 10, 1)),
      LendedMoney(
          id: 'owed',
          personId: 'x',
          amount: 20,
          type: 'borrowed',
          date: DateTime(2026, 10, 1)),
      LendedMoney(
          id: 'done',
          personId: 'x',
          amount: 999,
          type: 'lent',
          date: DateTime(2026, 10, 1),
          isSettled: true),
    ], assets: [
      AssetItem(
          id: 'car',
          name: 'car',
          value: 500,
          currency: 'BRL',
          createdAt: DateTime(2026, 10, 2))
    ], convert: same);
    expect(data.claimsAt(DateTime(2026, 9, 30)), -1000);
    expect(data.claimsAt(DateTime(2026, 10, 31)), -700 + 50 - 20);
    expect(data.assetsAt(DateTime(2026, 9, 30)), 0);
    expect(data.assetsAt(DateTime(2026, 10, 31)), 500);
  });

  test('pending and off-balance entries never moved the balance', () {
    final data = NetWorthInputs(accounts: [
      account('bank', 'bank', 1000),
      account('off', 'bank', 999, excluded: true),
    ], transactions: [
      tx('in', 'income', 1000, DateTime(2026, 9, 1)),
      tx('pending', 'expense', 500, DateTime(2026, 10, 15)),
      tx('off', 'expense', 70, DateTime(2026, 10, 16)),
    ], metadata: {
      'pending': const TransactionMetadata(
          transactionId: 'pending', status: 'pending'),
      'off': const TransactionMetadata(
          transactionId: 'off', affectsBalance: false),
    }, positions: const [], convert: same);
    expect(netWorthHistory(data, now: now, months: 2).map((p) => p.cash),
        [1000, 1000]);
  });

  test('an old snapshot gains what it never held, and only that', () {
    final data = NetWorthInputs(
        accounts: const [],
        transactions: const [],
        metadata: const {},
        positions: [
          InvestmentPosition(stock('A'), [
            op('b', 'A', 'buy', 1, 10000, DateTime(2026, 10, 1)),
          ])
        ],
        convert: same);
    NetWorthSnapshot snap(String date) => NetWorthSnapshot(
        id: date,
        date: date,
        totalAccounts: 50,
        totalAssets: 0,
        netWorth: 50,
        currency: 'BRL');
    expect(data.snapshotTotal(snap('2026-09-30')), 50);
    expect(data.snapshotTotal(snap('2026-10-02')), 150);
  });

  test('with nothing recorded there is only today', () {
    final points = netWorthHistory(
        NetWorthInputs(
            accounts: [account('bank', 'bank', 80)],
            transactions: const [],
            metadata: const {},
            positions: const [],
            convert: same),
        now: now);
    expect(points.single.total, 80);
  });
}
