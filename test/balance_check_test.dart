import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/balance_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final read = DateTime(2026, 10, 22, 6);
  Account account(double balance, {String type = 'bank'}) => Account(
      id: 'mp',
      name: 'Conta principal',
      type: type,
      balance: balance,
      currency: 'BRL',
      colorValue: 0);
  AppTransaction tx(String id, double amount, DateTime date,
          {String type = 'expense'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: id,
          accountId: 'mp',
          categoryId: 'c',
          date: date);
  BankAccountSnapshot bank(int? cents,
          {String type = 'BANK', int? limit, int? available}) =>
      BankAccountSnapshot(
          accountId: 'p1',
          bank: 'Mercado Pago',
          type: type,
          name: 'Conta',
          currency: 'BRL',
          balanceCents: cents,
          creditLimitCents: limit,
          availableCents: available,
          bankUpdatedAt: read);

  test('session case: bank -R\$ 33, Nexo different, compared at the bank read',
      () {
    // Nexo today R$ 10, with a R$ 20 lunch entered after the bank read and
    // a pending bill that never moved the balance.
    final c =
        checkBalance(account: account(10), bank: bank(-3300), transactions: [
      tx('lunch', 20, DateTime(2026, 10, 22, 12)),
      tx('bill', 99, DateTime(2026, 10, 23)),
      tx('before', 5, DateTime(2026, 10, 21)),
    ], metadata: {
      'bill':
          const TransactionMetadata(transactionId: 'bill', status: 'pending')
    })!;
    expect(c.nexoAtBankCents, 3000); // 10 + 20 back
    expect(c.bankCents, -3300);
    expect(c.differenceCents, -6300);
    expect(c.laterEntries.map((t) => t.id), ['lunch']);
    expect(c.matches, isFalse);
  });

  test('a card is a debt: limit minus available when the bank gives both', () {
    final c = checkBalance(
        account: account(-634.51, type: 'credit'),
        bank: bank(21359, type: 'CREDIT', limit: 65000, available: 1549),
        transactions: const [],
        metadata: const {})!;
    expect(c.bankCents, -63451);
    expect(c.matches, isTrue);
    // Without limits, the open invoice balance.
    expect(
        checkBalance(
                account: account(-213.59, type: 'credit'),
                bank: bank(21359, type: 'CREDIT'),
                transactions: const [],
                metadata: const {})!
            .matches,
        isTrue);
  });

  test('no bank balance or another currency: no comparison, no guess', () {
    expect(
        checkBalance(
            account: account(10),
            bank: bank(null),
            transactions: const [],
            metadata: const {}),
        isNull);
    final usd = BankAccountSnapshot(
        accountId: 'x',
        bank: 'B',
        type: 'BANK',
        name: 'n',
        currency: 'USD',
        balanceCents: 100);
    expect(
        checkBalance(
            account: account(1),
            bank: usd,
            transactions: const [],
            metadata: const {}),
        isNull);
  });

  test('server rows parse; dates come in local time', () {
    final s = BankAccountSnapshot.fromJson({
      'account_id': 'acc',
      'bank': 'Nubank',
      'type': 'CREDIT',
      'name': 'Cartão',
      'currency': 'BRL',
      'balance_cents': 21359,
      'credit_limit_cents': 65000,
      'available_cents': 1549,
      'due_date': '2026-11-26',
      'bank_updated_at': '2026-10-22T06:00:00+00:00',
      'nexo_account_id': 'nu',
    });
    expect(s.isCard, isTrue);
    expect(s.nexoSignedCents, -63451);
    expect(s.bankUpdatedAt!.toUtc(), DateTime.utc(2026, 10, 22, 6));
    expect(s.nexoAccountId, 'nu');
  });

  test('one Nexo account holding every bank: balances summed, oldest read', () {
    BankAccountSnapshot one(String id, String name, int? cents, DateTime at,
            {String currency = 'BRL', String type = 'BANK'}) =>
        BankAccountSnapshot(
            accountId: id,
            bank: name,
            type: type,
            name: 'Conta',
            currency: currency,
            balanceCents: cents,
            nexoAccountId: 'mp',
            bankUpdatedAt: at);
    final group = [
      one('a', 'Nubank', 10000, read),
      one('b', 'Inter', 5000, read.subtract(const Duration(hours: 5))),
      one('c', 'BTG', -1000, read.add(const Duration(hours: 1))),
    ];
    final all = combineBankAccounts(group)!;
    expect(all.balanceCents, 14000);
    expect(all.bankUpdatedAt, read.subtract(const Duration(hours: 5)));
    expect(all.bank, 'Nubank + Inter + BTG');
    expect(all.isCard, isFalse);
    final c = checkBalance(
        account: account(10),
        bank: all,
        transactions: const [],
        metadata: const {});
    expect(c!.differenceCents, 13000);
    // Never a guess: a missing balance, another currency or a card.
    expect(combineBankAccounts([...group, one('d', 'X', null, read)]), isNull);
    expect(
        combineBankAccounts(
            [...group, one('d', 'X', 1, read, currency: 'USD')]),
        isNull);
    expect(
        combineBankAccounts([...group, one('d', 'X', 1, read, type: 'CREDIT')]),
        isNull);
    expect(combineBankAccounts([group.first]), same(group.first));
    expect(combineBankAccounts(const []), isNull);
  });
}
