import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/services/loan_ledger.dart';
import 'package:nexo/providers/app_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LoanLedger ledger;
  Loan loan() => Loan(
      id: 'loan',
      name: 'Sintético',
      principal: 1000,
      currency: 'BRL',
      startDate: DateTime(2026, 1),
      endDate: DateTime(2026, 11),
      transferAccountId: 'bank',
      accountId: 'bank');
  LoanPayment payment(String id, double amount, {String account = 'bank'}) =>
      LoanPayment(
          id: id,
          loanId: 'loan',
          date: DateTime(2026, 10, 19),
          amount: amount,
          currency: 'BRL',
          accountId: account);
  Future<double> balance() async =>
      (await DBHelper.getAccounts()).single.balance;
  setUp(() async {
    await DBHelper.close();
    final directory =
        await Directory.systemTemp.createTemp('nexo-loan-atomic-');
    await DatabasePlatform.initialize(testDirectory: directory.path);
    final db = await DBHelper.database;
    ledger = LoanLedger(db);
    await DBHelper.insertAccount(Account(
        id: 'bank',
        name: 'Sintético',
        type: 'bank',
        currency: 'BRL',
        balance: 1000,
        colorValue: 0));
  });
  tearDown(() => DBHelper.close());

  test('retry a stable payment id never debits twice; changed content rejects',
      () async {
    await ledger.create(loan());
    await ledger.pay(payment('p1', 100));
    await ledger.pay(payment('p1', 100));
    expect(await balance(), 1900);
    expect((await DBHelper.getAllLoanPayments()).length, 1);
    await expectLater(ledger.pay(payment('p1', 200)), throwsStateError);
    expect(await balance(), 1900);
  });

  test('failed payment or principal move rolls back the whole aggregate',
      () async {
    await expectLater(
        ledger.create(loan().copyWith(transferAccountId: 'missing')),
        throwsStateError);
    expect(await DBHelper.getLoans(), isEmpty);
    expect(await balance(), 1000);
    await ledger.create(loan());
    await expectLater(
        ledger.pay(payment('p1', 100, account: 'missing')), throwsStateError);
    expect(await DBHelper.getAllLoanPayments(), isEmpty);
    expect(await balance(), 2000);
    await expectLater(
        ledger.update(loan().copyWith(transferAccountId: 'missing')),
        throwsStateError);
    expect(await balance(), 2000);
    expect((await DBHelper.getLoans()).single.transferAccountId, 'bank');
  });

  test('settlement counts each payment once and reversal reopens debt',
      () async {
    await ledger.create(loan());
    await ledger.pay(payment('p1', 600));
    expect((await DBHelper.getLoans()).single.isSettled, false);
    await ledger.pay(payment('p2', 400));
    expect((await DBHelper.getLoans()).single.isSettled, true);
    await ledger.removePayment('p2');
    await ledger.removePayment('p2');
    expect((await DBHelper.getLoans()).single.isSettled, false);
    expect(await balance(), 1400);
  });

  test('delete and undo preserve all principal and payment effects atomically',
      () async {
    await ledger.create(loan());
    await ledger.pay(payment('p1', 100));
    final removed = await ledger.remove('loan');
    expect(await balance(), 1000);
    expect(await DBHelper.getLoans(), isEmpty);
    expect(await DBHelper.getAllLoanPayments(), isEmpty);
    await ledger.create(removed.loan, payments: removed.payments);
    expect(await balance(), 1900);
    await expectLater(ledger.create(removed.loan, payments: removed.payments),
        throwsA(anything));
    expect(await balance(), 1900);
  });

  test('provider does not settle a 1000 debt after paying only 600', () async {
    final app = AppProvider();
    await app.addLoan(loan());
    await app.payLoanInstallment(loan(), amount: 600);
    expect(app.loans.single.isSettled, false);
    expect(app.loanTotalPaid(app.loans.single), 600);
    expect(await balance(), 1400);
    app.dispose();
  });
}
