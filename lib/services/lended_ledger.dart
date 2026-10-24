import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/models.dart';
import '../sync/ledger_capture.dart';

/// Money lent to or borrowed from a person, and its account effect, in one
/// SQLite commit. State is always read from the database, never from a
/// possibly stale screen, so a repeated tap cannot move money twice.
///
/// An open entry linked to an account has already moved that account. While
/// it stays open the effect remains; settling returns it; deleting an open
/// entry reverses it, like deleting a transaction or a loan. Settled entries
/// net to zero, so deleting them moves nothing.
class LendedLedger {
  LendedLedger(this.db);
  final Database db;

  static double _effect(LendedMoney l) =>
      l.type == 'lent' ? -l.amount : l.amount;

  void _validate(LendedMoney l) {
    if (!l.amount.isFinite || l.amount <= 0) {
      throw const FormatException('Informe um valor positivo.');
    }
    if (!['lent', 'borrowed'].contains(l.type)) {
      throw const FormatException('Tipo de registro inválido.');
    }
  }

  Future<LendedMoney?> _entry(DatabaseExecutor tx, String id) async {
    final rows = await tx.query('lended_money', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : LendedMoney.fromMap(rows.single);
  }

  /// [strict] requires the account to exist (new effects). Reversals of old
  /// entries tolerate an account deleted meanwhile, as before.
  Future<void> _move(DatabaseExecutor tx, LendedMoney l, double sign,
      {required bool strict}) async {
    if (l.accountId == null || l.isSettled) return;
    final rows =
        await tx.query('accounts', where: 'id=?', whereArgs: [l.accountId]);
    if (rows.isEmpty) {
      if (strict) throw StateError('Conta não encontrada.');
      return;
    }
    // Gold balances derive from grams and price; never moved by entries.
    if (rows.single['type'] == 'gold') return;
    await tx.rawUpdate('UPDATE accounts SET balance=balance+? WHERE id=?',
        [sign * _effect(l), l.accountId]);
  }

  Future<void> _insert(DatabaseExecutor tx, LendedMoney l) async {
    _validate(l);
    final existing = await _entry(tx, l.id);
    if (existing != null) {
      // Retry of the same record is a no-op; a different one is an error.
      if (mapEquals(existing.toMap(), l.toMap())) return;
      throw StateError('Registro já existe com outro conteúdo.');
    }
    if ((await tx.query('lended_people',
            where: 'id=?', whereArgs: [l.personId], limit: 1))
        .isEmpty) {
      throw StateError('Pessoa não encontrada.');
    }
    await tx.insert('lended_money', l.toMap());
    await _move(tx, l, 1, strict: true);
  }

  Future<void> add(LendedMoney l) =>
      ledgerTransaction(db, 'lended.add', (tx) => _insert(tx, l));

  Future<void> update(LendedMoney updated) =>
      ledgerTransaction(db, 'lended.update', (tx) async {
        _validate(updated);
        final original = await _entry(tx, updated.id);
        if (original == null) throw StateError('Registro não encontrado.');
        await _move(tx, original, -1, strict: false);
        await _move(tx, updated, 1, strict: true);
        await tx.update('lended_money', updated.toMap(),
            where: 'id=?', whereArgs: [updated.id]);
      });

  /// Returns false when the entry was already settled or no longer exists.
  Future<bool> settle(String id) =>
      ledgerTransaction(db, 'lended.settle', (tx) async {
        final entry = await _entry(tx, id);
        if (entry == null || entry.isSettled) return false;
        await _move(tx, entry, -1, strict: false);
        await tx.update('lended_money', {'is_settled': 1},
            where: 'id=?', whereArgs: [id]);
        return true;
      });

  Future<LendedMoney?> remove(String id) =>
      ledgerTransaction(db, 'lended.delete', (tx) async {
        final entry = await _entry(tx, id);
        if (entry == null) return null;
        await _move(tx, entry, -1, strict: false);
        await tx.delete('lended_money', where: 'id=?', whereArgs: [id]);
        return entry;
      });

  /// Undo of [remove]: the entry and its open effect return together.
  Future<void> restore(LendedMoney entry) =>
      ledgerTransaction(db, 'lended.restore', (tx) => _insert(tx, entry));

  Future<({LendedPerson person, List<LendedMoney> entries})?> removePerson(
          String personId) =>
      ledgerTransaction(db, 'lended_person.delete', (tx) async {
        final people = await tx
            .query('lended_people', where: 'id=?', whereArgs: [personId]);
        if (people.isEmpty) return null;
        final entries = (await tx.query('lended_money',
                where: 'person_id=?', whereArgs: [personId]))
            .map(LendedMoney.fromMap)
            .toList();
        for (final entry in entries) {
          await _move(tx, entry, -1, strict: false);
        }
        await tx.delete('lended_money',
            where: 'person_id=?', whereArgs: [personId]);
        await tx.delete('lended_people', where: 'id=?', whereArgs: [personId]);
        return (person: LendedPerson.fromMap(people.single), entries: entries);
      });

  Future<void> restorePerson(LendedPerson person, List<LendedMoney> entries) =>
      ledgerTransaction(db, 'lended_person.restore', (tx) async {
        await tx.insert('lended_people', person.toMap());
        for (final entry in entries) {
          await _insert(tx, entry);
        }
      });
}
