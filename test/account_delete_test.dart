import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/services/lended_ledger.dart';
import 'package:expensy/services/loan_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic accounts in a temporary database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Account account(String id, {double balance = 0}) => Account(
      id: id,
      name: 'Conta $id',
      type: 'bank',
      balance: balance,
      currency: 'BRL',
      colorValue: 0);
  Future<List<String>> ids() async =>
      (await DBHelper.getAccounts()).map((a) => a.id).toList();

  setUp(() async {
    await DBHelper.close();
    final directory = await Directory.systemTemp.createTemp('nexo-account-');
    await DatabasePlatform.initialize(testDirectory: directory.path);
    await DBHelper.insertAccount(account('bank', balance: 500));
  });
  tearDown(DBHelper.close);

  test('an account without dependencies is deleted', () async {
    await DBHelper.insertAccount(account('empty'));
    await DBHelper.deleteAccount('empty');
    expect(await ids(), ['bank']);
  });

  test('history is never deleted in cascade', () async {
    final db = await DBHelper.database;
    await DBHelper.operation(
        'test.seed',
        (txn) => txn.insert(
            'transactions',
            AppTransaction(
                    id: 't1',
                    type: 'expense',
                    amount: 10,
                    description: 'Sintético',
                    accountId: 'bank',
                    categoryId: 'food_exp',
                    date: DateTime(2026, 10, 1))
                .toMap()));
    await expectLater(DBHelper.deleteAccount('bank'), throwsFormatException);
    expect(await ids(), ['bank']);
    expect(await db.query('transactions'), hasLength(1));
  });

  test('open lended entries and loans block deletion; settled ones do not',
      () async {
    final db = await DBHelper.database;
    await DBHelper.insertLendedPerson(
        LendedPerson(id: 'ana', name: 'Ana', colorValue: 0));
    final lended = LendedLedger(db);
    await lended.add(LendedMoney(
        id: 'l1',
        personId: 'ana',
        amount: 50,
        type: 'lent',
        accountId: 'bank',
        date: DateTime(2026, 10, 1)));
    await expectLater(DBHelper.deleteAccount('bank'), throwsFormatException);
    await lended.settle('l1');

    await LoanLedger(db).create(Loan(
        id: 'loan',
        name: 'Sintético',
        principal: 100,
        currency: 'BRL',
        startDate: DateTime(2026, 1),
        endDate: DateTime(2026, 12),
        transferAccountId: 'bank'));
    await expectLater(DBHelper.deleteAccount('bank'), throwsFormatException);
    await LoanLedger(db).remove('loan');

    await DBHelper.deleteAccount('bank');
    expect(await ids(), isEmpty);
  });

  test('a linked card or a recurring rule blocks deletion', () async {
    await DBHelper.insertAccount(Account(
        id: 'card',
        name: 'Cartão',
        type: 'credit',
        balance: 0,
        currency: 'BRL',
        colorValue: 0,
        linkedAccountId: 'bank'));
    await expectLater(DBHelper.deleteAccount('bank'), throwsFormatException);
    await DBHelper.insertRecurring(RecurringPayment(
        id: 'r',
        name: 'Assinatura',
        accountId: 'card',
        categoryId: 'bills',
        amount: 10,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(2026, 10),
        nextDate: DateTime(2026, 11)));
    await expectLater(DBHelper.deleteAccount('card'), throwsFormatException);
    expect(await ids(), containsAll(['bank', 'card']));
  });
}
