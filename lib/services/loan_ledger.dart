import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/models.dart';
import '../sync/ledger_capture.dart';

/// One SQLite commit for each loan and all of its cash effects. This is the
/// domain boundary a sync journal can observe; no network work happens here.
class LoanLedger {
  LoanLedger(this.db);
  final Database db;

  Future<Loan> _loan(DatabaseExecutor tx, String id) async {
    final rows = await tx.query('loans', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('Empréstimo não encontrado.');
    return Loan.fromMap(rows.single);
  }

  Future<void> _move(
      DatabaseExecutor tx, String? id, double amount, String currency) async {
    if (id == null || amount == 0) return;
    if (!amount.isFinite) throw const FormatException('Valor inválido.');
    final rows = await tx.query('accounts', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty) throw StateError('Conta não encontrada.');
    if (rows.single['currency'] != currency) {
      throw const FormatException('Escolha uma conta na moeda do empréstimo.');
    }
    await tx.rawUpdate(
        'UPDATE accounts SET balance=balance+? WHERE id=?', [amount, id]);
  }

  void _validate(Loan loan) {
    if (!loan.principal.isFinite ||
        loan.principal <= 0 ||
        !loan.totalPayable.isFinite ||
        loan.totalPayable <= 0) {
      throw const FormatException('Valor do empréstimo inválido.');
    }
  }

  Future<void> create(Loan loan, {List<LoanPayment> payments = const []}) =>
      ledgerTransaction(db, payments.isEmpty ? 'loan.create' : 'loan.restore',
          (tx) async {
        _validate(loan);
        await tx.insert('loans', loan.toMap());
        await _move(tx, loan.transferAccountId, loan.principal, loan.currency);
        for (final payment in payments) {
          if (payment.loanId != loan.id)
            throw const FormatException('Parcela inválida.');
          await _payment(tx, loan, payment);
        }
      });

  Future<void> update(Loan loan) =>
      ledgerTransaction(db, 'loan.update', (tx) async {
        _validate(loan);
        final old = await _loan(tx, loan.id);
        final payments = await tx
            .query('loan_payments', where: 'loan_id=?', whereArgs: [loan.id]);
        if (old.currency != loan.currency && payments.isNotEmpty) {
          throw const FormatException(
              'Não altere a moeda de um empréstimo com parcelas registradas.');
        }
        await _move(tx, old.transferAccountId, -old.principal, old.currency);
        await _move(tx, loan.transferAccountId, loan.principal, loan.currency);
        await tx
            .update('loans', loan.toMap(), where: 'id=?', whereArgs: [loan.id]);
      });

  Future<({Loan loan, List<LoanPayment> payments})> remove(String id) =>
      ledgerTransaction(db, 'loan.delete', (tx) async {
        final loan = await _loan(tx, id);
        final payments = (await tx
                .query('loan_payments', where: 'loan_id=?', whereArgs: [id]))
            .map(LoanPayment.fromMap)
            .toList();
        await _move(tx, loan.transferAccountId, -loan.principal, loan.currency);
        for (final p in payments) {
          await _move(tx, p.accountId, p.amount, p.currency);
        }
        await tx.delete('loan_payments', where: 'loan_id=?', whereArgs: [id]);
        await tx.delete('loans', where: 'id=?', whereArgs: [id]);
        return (loan: loan, payments: payments);
      });

  Future<void> _payment(
      DatabaseExecutor tx, Loan loan, LoanPayment payment) async {
    if (!payment.amount.isFinite ||
        payment.amount < 0 ||
        payment.currency != loan.currency) {
      throw const FormatException('Valor ou moeda da parcela inválidos.');
    }
    final previous =
        await tx.query('loan_payments', where: 'id=?', whereArgs: [payment.id]);
    if (previous.isNotEmpty) {
      if (!mapEquals(previous.single, payment.toMap())) {
        throw StateError('Identificador de parcela já utilizado.');
      }
      return; // Same command is safe to retry; never debit twice.
    }
    await tx.insert('loan_payments', payment.toMap());
    await _move(tx, payment.accountId, -payment.amount, payment.currency);
    final total = (await tx.rawQuery(
            'SELECT COALESCE(SUM(amount),0) AS total FROM loan_payments WHERE loan_id=?',
            [loan.id]))
        .single['total'] as num;
    if ((total * 100).round() >= (loan.totalPayable * 100).round()) {
      await tx.update('loans', {'is_settled': 1},
          where: 'id=?', whereArgs: [loan.id]);
    }
  }

  Future<void> pay(LoanPayment payment) =>
      ledgerTransaction(db, 'loan.pay', (tx) async {
        final loan = await _loan(tx, payment.loanId);
        await _payment(tx, loan, payment);
      });

  Future<LoanPayment?> removePayment(String id) =>
      ledgerTransaction(db, 'loan.remove_payment', (tx) async {
        final rows =
            await tx.query('loan_payments', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) return null;
        final payment = LoanPayment.fromMap(rows.single);
        final loan = await _loan(tx, payment.loanId);
        await _move(tx, payment.accountId, payment.amount, payment.currency);
        await tx.delete('loan_payments', where: 'id=?', whereArgs: [id]);
        final total = (await tx.rawQuery(
                'SELECT COALESCE(SUM(amount),0) AS total FROM loan_payments WHERE loan_id=?',
                [loan.id]))
            .single['total'] as num;
        if ((total * 100).round() < (loan.totalPayable * 100).round()) {
          await tx.update('loans', {'is_settled': 0},
              where: 'id=?', whereArgs: [loan.id]);
        }
        return payment;
      });
}
