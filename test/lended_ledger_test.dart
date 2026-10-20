import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/lended_ledger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

// Synthetic people and accounts in a temporary database.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LendedLedger ledger;

  LendedMoney entry(String id, double amount,
          {String type = 'lent', String? account = 'bank'}) =>
      LendedMoney(
          id: id,
          personId: 'ana',
          amount: amount,
          type: type,
          accountId: account,
          date: DateTime(2026, 10, 1));
  Future<double> balance([String id = 'bank']) async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;
  Future<void> undo(VoidCallback callback) =>
      (callback as Future<void> Function())();

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await DBHelper.close();
    final directory = await Directory.systemTemp.createTemp('nexo-lended-');
    await DatabasePlatform.initialize(testDirectory: directory.path);
    ledger = LendedLedger(await DBHelper.database);
    await DBHelper.insertAccount(Account(
        id: 'bank',
        name: 'Banco sintético',
        type: 'bank',
        balance: 1000,
        currency: 'BRL',
        colorValue: 0));
    await DBHelper.insertAccount(Account(
        id: 'gold',
        name: 'Ouro sintético',
        type: 'gold',
        balance: 500,
        currency: 'BRL',
        colorValue: 0));
    await DBHelper.insertLendedPerson(
        LendedPerson(id: 'ana', name: 'Ana', colorValue: 0));
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
  });

  test('lending and borrowing move the account once; retries are harmless',
      () async {
    await ledger.add(entry('l1', 100));
    await ledger.add(entry('l1', 100));
    await ledger.add(entry('b1', 50, type: 'borrowed'));
    expect(await balance(), 950);
    await expectLater(ledger.add(entry('l1', 999)), throwsStateError);
    expect(await balance(), 950);
  });

  test('settling twice returns the money only once', () async {
    await ledger.add(entry('l1', 100));
    expect(await ledger.settle('l1'), true);
    expect(await ledger.settle('l1'), false);
    expect(await balance(), 1000);
    expect((await DBHelper.getLended()).single.isSettled, true);
  });

  test('deleting an open entry reverses it; undo reapplies; settled is zero',
      () async {
    await ledger.add(entry('l1', 100));
    final removed = await ledger.remove('l1');
    expect(await balance(), 1000);
    await ledger.restore(removed!);
    expect(await balance(), 900);
    await ledger.settle('l1');
    await ledger.remove('l1');
    expect(await balance(), 1000, reason: 'settled entries net to zero');
    expect(await ledger.remove('l1'), isNull);
  });

  test('editing reverses the stored entry, not the one shown on screen',
      () async {
    await ledger.add(entry('l1', 100));
    await ledger.update(entry('l1', 60));
    expect(await balance(), 940);
    await ledger.update(entry('l1', 60).copyWith(isSettled: true));
    expect(await balance(), 1000);
    await ledger.update(entry('l1', 30));
    expect(await balance(), 970, reason: 'reopening applies the new amount');
  });

  test('deleting a person reverses open entries and undo restores them',
      () async {
    await ledger.add(entry('l1', 100));
    await ledger.add(entry('l2', 40));
    await ledger.settle('l2');
    final removed = await ledger.removePerson('ana');
    expect(await balance(), 1000);
    expect(await DBHelper.getLended(), isEmpty);
    await ledger.restorePerson(removed!.person, removed.entries);
    expect(await balance(), 900);
    expect((await DBHelper.getLended()).length, 2);
  });

  test('a failed entry changes nothing; gold balances are never moved',
      () async {
    await expectLater(
        ledger.add(entry('l1', 100, account: 'missing')), throwsStateError);
    expect(await DBHelper.getLended(), isEmpty);
    await expectLater(ledger.add(entry('l2', -5)), throwsFormatException);
    await ledger.add(entry('l3', 100, account: 'gold'));
    expect(await balance('gold'), 500);
  });

  test('provider no longer writes balances from a stale in-memory copy',
      () async {
    final app = AppProvider();
    app.settings.budgetAlertsEnabled = false;
    app.accounts = await DBHelper.getAccounts();
    app.lendedPeople = await DBHelper.getLendedPeople();
    // Another flow changes the stored balance; app.accounts stays at 1000.
    await DBHelper.operation(
        'test.change',
        (txn) => txn.rawUpdate(
            'UPDATE accounts SET balance = balance - 300 WHERE id = ?',
            ['bank']));
    await app.addLended(entry('l1', 100));
    expect(await balance(), 600, reason: 'old code wrote 1000 - 100');
    await app.settleLended(app.lended.single);
    await app.settleLended(app.lended.single.copyWith(isSettled: false));
    expect(await balance(), 700);
    final undoDelete = await app.deleteLendedWithUndo('l1');
    expect(await balance(), 700, reason: 'settled entry: nothing to reverse');
    await undo(undoDelete);
    expect(await balance(), 700);
    app.dispose();
  });
}
