// What using the app on a real phone turned up. Fictitious figures only.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/services/entry_defaults.dart';
import 'package:nexo/services/finance_rules.dart';

void main() {
  AppTransaction tx(String id, String type, String account) => AppTransaction(
      id: id,
      type: type,
      amount: 10,
      description: id,
      accountId: account,
      categoryId: 'c',
      date: DateTime(2026, 11, 3),
      currency: 'BRL');
  Account account(String id, String type,
          {double balance = 0, double? limit}) =>
      Account(
          id: id,
          name: id,
          type: type,
          balance: balance,
          currency: 'BRL',
          colorValue: 0,
          creditLimit: limit);

  group('invoice', () {
    test('a forecast credit does not lower it', () {
      expect(
          FinanceRules.onInvoice(tx('c', 'income', 'card'),
              const TransactionMetadata(transactionId: 'c', status: 'pending')),
          isFalse);
    });

    test('a credit that happened does', () {
      expect(
          FinanceRules.onInvoice(tx('c', 'income', 'card'),
              const TransactionMetadata(transactionId: 'c')),
          isTrue);
    });

    test('a purchase is on it, even pending', () {
      expect(
          FinanceRules.onInvoice(tx('p', 'expense', 'card'),
              const TransactionMetadata(transactionId: 'p', status: 'pending')),
          isTrue);
    });
  });

  group('default account', () {
    final accounts = [account('card', 'credit'), account('bank', 'bank')];

    test('income never starts on a card', () {
      expect(
          EntryDefaults.recentAccount(
                  accounts, [tx('i', 'income', 'card')], const {}, 'income')
              ?.id,
          'bank');
    });

    test('income with no history starts on the first real account', () {
      expect(
          EntryDefaults.recentAccount(accounts, const [], const {}, 'income')
              ?.id,
          'bank');
    });

    test('an expense still follows the last one', () {
      expect(
          EntryDefaults.recentAccount(
                  accounts, [tx('e', 'expense', 'card')], const {}, 'expense')
              ?.id,
          'card');
    });
  });

  group('free limit', () {
    test('what is left of a card', () {
      expect(
          EntryDefaults.freeLimit(
              account('c', 'credit', balance: -300, limit: 500)),
          200);
    });

    test('over the limit is negative', () {
      expect(
          EntryDefaults.freeLimit(
              account('c', 'credit', balance: -510, limit: 500)),
          -10);
    });

    test('a credit balance does not raise the limit', () {
      expect(
          EntryDefaults.freeLimit(
              account('c', 'credit', balance: 20, limit: 500)),
          500);
    });

    test('nothing for a bank or a card with no limit', () {
      expect(EntryDefaults.freeLimit(account('b', 'bank', limit: 500)), isNull);
      expect(EntryDefaults.freeLimit(account('c', 'credit')), isNull);
    });
  });

  test('no machine translation left in the Portuguese texts', () {
    final text = File('lib/l10n/app_pt.arb').readAsStringSync();
    final values = (jsonDecode(text) as Map<String, dynamic>)
        .entries
        .where((e) => !e.key.startsWith('@'))
        .map((e) => '${e.value}');
    for (final bad in [
      'Quaresma',
      'emprestado ou emprestado',
      'Editar recurso'
    ]) {
      expect(values.where((v) => v.contains(bad)), isEmpty, reason: bad);
    }
  });

  test('no English left on the loan screens', () {
    for (final f in [
      'lib/screens/loans_screen.dart',
      'lib/screens/loan_detail_screen.dart'
    ]) {
      final text = File(f).readAsStringSync();
      for (final bad in [
        'Transfer Loan',
        'Pay Installments',
        "'Interest Rate'",
        "'Duration'"
      ]) {
        expect(text.contains(bad), isFalse, reason: bad);
      }
    }
  });

  test('nothing says deleted or Undo to the person', () {
    for (final dir in ['lib/screens', 'lib/widgets', 'lib/utils']) {
      for (final f in Directory(dir).listSync().whereType<File>()) {
        final text = f.readAsStringSync();
        expect(text.contains("} deleted'"), isFalse, reason: f.path);
        expect(text.contains("label: 'Undo'"), isFalse, reason: f.path);
      }
    }
  });
}
