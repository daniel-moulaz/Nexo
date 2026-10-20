import 'dart:collection';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'sync_protocol.dart' show canonicalSyncJson;

/// User data that must travel between devices, keyed by primary key column.
/// Every table in the database must be listed here or in [ledgerLocalTables];
/// a test enforces it so a new table forces an explicit decision.
const ledgerTables = <String, String>{
  'accounts': 'id',
  'categories': 'id',
  'transactions': 'id',
  'transaction_metadata': 'transaction_id',
  'card_invoice_payments': 'id',
  'recurring_payments': 'id',
  'recurring_history': 'id',
  'wishlist': 'id',
  'lended_people': 'id',
  'lended_money': 'id',
  'assets': 'id',
  'budgets': 'id',
  'savings_goals': 'id',
  'savings_contributions': 'id',
  'loans': 'id',
  'loan_payments': 'id',
  'investments': 'id',
  'investment_operations': 'id',
  'import_rules': 'id',
};

/// Device-local or derived state: bank notification inbox of this phone,
/// daily net-worth snapshots computed by each device and a legacy table.
const ledgerLocalTables = {
  'notification_suggestions',
  'net_worth_snapshots',
  'asset_items',
};

/// `user`: a decision of the person, journaled exactly once.
/// `derived`: values recomputed by each device (gold price, quotes); captured
/// rows are discarded so another device never replays them as money.
/// `restore`: a backup replaced the ledger; nothing is journaled and a
/// persistent barrier demands a new bootstrap before any future sync.
/// `remote`: applying an operation that came from another device.
enum LedgerScope { user, derived, restore, remote }

const ledgerJournalFormat = 1;

class LedgerConflict implements Exception {
  const LedgerConflict(this.code);
  final String code;
  @override
  String toString() => 'LedgerConflict($code)';
}

final _installed = Expando<bool>('ledgerCapture');

/// Runs [body] as one SQLite transaction and one named domain operation.
/// Without installed capture (every production database today) this is a
/// plain transaction: no table, trigger or journal row is created.
Future<T> ledgerTransaction<T>(
  Database db,
  String kind,
  Future<T> Function(Transaction txn) body, {
  LedgerScope scope = LedgerScope.user,
}) async {
  if (!await LedgerCapture.isInstalled(db)) return db.transaction(body);
  return db.transaction((txn) async {
    final id = const Uuid().v4();
    // A second context row fails the CHECK: nested operations are a bug.
    await txn.insert('sync_capture_context',
        {'singleton': 1, 'operation_id': id, 'kind': kind});
    final result = await body(txn);
    await LedgerCapture._finalize(txn, id, kind, scope);
    await txn.delete('sync_capture_context');
    return result;
  });
}

/// Trigger-based change capture. Installed explicitly (synthetic tests now;
/// sync activation later). Cascades, REPLACE inserts and raw SQL are seen
/// because SQLite itself reports the row changes, not each call site.
abstract final class LedgerCapture {
  static Future<bool> isInstalled(Database db) async {
    final cached = _installed[db];
    if (cached != null) return cached;
    final rows = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sync_capture_state'");
    return _installed[db] = rows.isNotEmpty;
  }

  static Future<void> install(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_capture_state (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        format INTEGER NOT NULL, restore_barrier INTEGER NOT NULL DEFAULT 0)''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_capture_context (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        operation_id TEXT NOT NULL, kind TEXT NOT NULL)''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_capture_log (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, operation_id TEXT,
        table_name TEXT NOT NULL, row_key TEXT, action TEXT NOT NULL)''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_capture_balance (
        seq INTEGER PRIMARY KEY AUTOINCREMENT, operation_id TEXT,
        account_id TEXT NOT NULL, delta REAL NOT NULL)''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_balance_shadow (
        account_id TEXT PRIMARY KEY, balance REAL NOT NULL)''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_entity_state (
        table_name TEXT NOT NULL, row_key TEXT NOT NULL,
        revision INTEGER NOT NULL, value_hash TEXT, deleted INTEGER NOT NULL,
        PRIMARY KEY(table_name, row_key))''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_applied (
        operation_id TEXT PRIMARY KEY)''');
      await txn.execute('''CREATE TABLE IF NOT EXISTS sync_journal (
        position INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT UNIQUE NOT NULL, kind TEXT NOT NULL,
        payload TEXT NOT NULL, hash TEXT NOT NULL, created_at TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending')''');
      if ((await txn.query('sync_capture_state')).isEmpty) {
        await txn.insert('sync_capture_state',
            {'singleton': 1, 'format': ledgerJournalFormat});
      }
      const context = '(SELECT operation_id FROM sync_capture_context)';
      for (final entry in ledgerTables.entries) {
        final t = entry.key, k = entry.value;
        await txn.execute('''CREATE TRIGGER IF NOT EXISTS sync_capture_${t}_ins
          AFTER INSERT ON $t BEGIN
            INSERT INTO sync_capture_log(operation_id, table_name, row_key, action)
            VALUES ($context, '$t', NEW.$k, 'upsert');
          END''');
        await txn.execute('''CREATE TRIGGER IF NOT EXISTS sync_capture_${t}_upd
          AFTER UPDATE ON $t BEGIN
            INSERT INTO sync_capture_log(operation_id, table_name, row_key, action)
            SELECT $context, '$t', OLD.$k, 'delete' WHERE OLD.$k IS NOT NEW.$k;
            INSERT INTO sync_capture_log(operation_id, table_name, row_key, action)
            VALUES ($context, '$t', NEW.$k, 'upsert');
          END''');
        await txn.execute('''CREATE TRIGGER IF NOT EXISTS sync_capture_${t}_del
          AFTER DELETE ON $t BEGIN
            INSERT INTO sync_capture_log(operation_id, table_name, row_key, action)
            VALUES ($context, '$t', OLD.$k, 'delete');
          END''');
      }
      // Balance is materialized: record what changed, never the total. The
      // shadow also covers INSERT OR REPLACE, which skips delete triggers.
      const shadow =
          'COALESCE((SELECT balance FROM sync_balance_shadow WHERE account_id = NEW.id), 0)';
      const record = '''
            INSERT INTO sync_capture_balance(operation_id, account_id, delta)
            SELECT $context, NEW.id, NEW.balance - $shadow
              WHERE NEW.balance IS NOT $shadow;
            INSERT OR REPLACE INTO sync_balance_shadow(account_id, balance)
            VALUES (NEW.id, NEW.balance);''';
      await txn.execute('''CREATE TRIGGER IF NOT EXISTS sync_capture_balance_ins
          AFTER INSERT ON accounts BEGIN $record END''');
      await txn.execute('''CREATE TRIGGER IF NOT EXISTS sync_capture_balance_upd
          AFTER UPDATE OF balance ON accounts BEGIN $record END''');
      await txn.execute('''CREATE TRIGGER IF NOT EXISTS sync_capture_balance_del
          AFTER DELETE ON accounts BEGIN
            DELETE FROM sync_balance_shadow WHERE account_id = OLD.id;
          END''');
      // Existing rows form the checkpoint: revision 1, never re-journaled.
      await txn.execute(
          'INSERT OR IGNORE INTO sync_balance_shadow SELECT id, balance FROM accounts');
      for (final entry in ledgerTables.entries) {
        for (final row in await txn.query(entry.key)) {
          await txn.insert(
              'sync_entity_state',
              {
                'table_name': entry.key,
                'row_key': '${row[entry.value]}',
                'revision': 1,
                'value_hash': await _hash(_value(entry.key, row)),
                'deleted': 0,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
    });
    _installed[db] = true;
  }

  /// Row changes made outside any [ledgerTransaction]. Sync must refuse to
  /// push while this is not zero: such a write would be silently lost.
  static Future<int> unattributedChanges(DatabaseExecutor db) async =>
      Sqflite.firstIntValue(await db.rawQuery(
          'SELECT (SELECT COUNT(*) FROM sync_capture_log WHERE operation_id IS NULL) + '
          '(SELECT COUNT(*) FROM sync_capture_balance WHERE operation_id IS NULL)'))!;

  static Future<List<Map<String, Object?>>> unattributedTables(
          DatabaseExecutor db) =>
      db.rawQuery('SELECT DISTINCT table_name FROM sync_capture_log '
          'WHERE operation_id IS NULL ORDER BY table_name');

  static Future<bool> restoreBarrier(DatabaseExecutor db) async =>
      (await db.query('sync_capture_state')).single['restore_barrier'] == 1;

  static Future<List<LedgerOperation>> journal(DatabaseExecutor db) async =>
      (await db.query('sync_journal', orderBy: 'position'))
          .map((r) => LedgerOperation.decode(r['payload'] as String))
          .toList();

  static Map<String, Object?> _value(String table, Map<String, Object?> row) {
    final value = Map<String, Object?>.from(row);
    // Balance travels as deltas; copying totals would erase concurrent work.
    if (table == 'accounts') value.remove('balance');
    return value;
  }

  static Future<String> _hash(Map<String, Object?> value) =>
      _digest(canonicalSyncJson(value));

  static Future<String> _digest(String text) async =>
      (await Sha256().hash(utf8.encode(text)))
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();

  static Future<Map<String, Object?>?> _entity(
      DatabaseExecutor txn, String table, String key) async {
    final rows = await txn.query('sync_entity_state',
        where: 'table_name = ? AND row_key = ?', whereArgs: [table, key]);
    return rows.isEmpty ? null : rows.single;
  }

  static Future<void> _setEntity(DatabaseExecutor txn, String table, String key,
          int revision, String? hash) =>
      txn.insert(
          'sync_entity_state',
          {
            'table_name': table,
            'row_key': key,
            'revision': revision,
            'value_hash': hash,
            'deleted': hash == null ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

  static Future<void> _finalize(
      Transaction txn, String id, String kind, LedgerScope scope) async {
    final logs = await txn.query('sync_capture_log',
        where: 'operation_id = ?', whereArgs: [id], orderBy: 'seq');
    final sums = await txn.rawQuery(
        'SELECT account_id, SUM(delta) AS delta FROM sync_capture_balance '
        'WHERE operation_id = ? GROUP BY account_id ORDER BY account_id',
        [id]);
    await txn
        .delete('sync_capture_log', where: 'operation_id = ?', whereArgs: [id]);
    await txn.delete('sync_capture_balance',
        where: 'operation_id = ?', whereArgs: [id]);
    switch (scope) {
      case LedgerScope.derived:
      case LedgerScope.remote:
        return;
      case LedgerScope.restore:
        await txn.update('sync_capture_state', {'restore_barrier': 1});
        return;
      case LedgerScope.user:
        break;
    }
    final touched = LinkedHashSet<(String, String)>();
    for (final log in logs) {
      touched.add((log['table_name'] as String, log['row_key'] as String));
    }
    final edits = <LedgerEdit>[];
    for (final (table, key) in touched) {
      final rows = await txn
          .query(table, where: '${ledgerTables[table]} = ?', whereArgs: [key]);
      final value = rows.isEmpty ? null : _value(table, rows.single);
      final state = await _entity(txn, table, key);
      final known = state != null && state['deleted'] == 0;
      final hash = value == null ? null : await _hash(value);
      // Created and removed inside one operation, or an unchanged row (for
      // instance an account whose only change was its balance).
      if (value == null && !known) continue;
      if (value != null && known && state['value_hash'] == hash) continue;
      final base = (state?['revision'] as int?) ?? 0;
      edits.add(LedgerEdit(table, key, base, value));
      await _setEntity(txn, table, key, base + 1, hash);
    }
    final balances = <LedgerBalanceDelta>[];
    for (final row in sums) {
      final micros = ((row['delta'] as num) * 1e6).round();
      if (micros == 0) continue;
      final account = row['account_id'] as String;
      final state = await _entity(txn, 'accounts', account);
      balances.add(LedgerBalanceDelta(
          account, micros, (state?['revision'] as int?) ?? 0));
    }
    if (edits.isEmpty && balances.isEmpty) return;
    final operation = LedgerOperation(
        id: id,
        kind: kind,
        createdAt: DateTime.now().toUtc(),
        edits: edits,
        balances: balances);
    final payload = operation.encode();
    await txn.insert('sync_journal', {
      'operation_id': id,
      'kind': kind,
      'payload': payload,
      'hash': await _digest(payload),
      'created_at': operation.createdAt.toIso8601String(),
    });
  }

  /// Applies another device's operation. Every entity it writes, and every
  /// account whose balance it moves, must be at the revision that operation
  /// saw; otherwise nothing is applied and the conflict is reported.
  static Future<void> apply(Database db, LedgerOperation op) =>
      ledgerTransaction(db, 'sync.apply', (txn) async {
        if (await restoreBarrier(txn)) {
          throw const LedgerConflict('restore_review_required');
        }
        // Redelivery (lost acknowledgement, repeated page) moves nothing.
        final seen = await txn.rawQuery(
            'SELECT 1 FROM sync_applied WHERE operation_id = ? '
            'UNION SELECT 1 FROM sync_journal WHERE operation_id = ?',
            [op.id, op.id]);
        if (seen.isNotEmpty) return;
        for (final edit in op.edits) {
          final state = await _entity(txn, edit.table, edit.key);
          if (((state?['revision'] as int?) ?? 0) != edit.baseRevision) {
            throw const LedgerConflict('concurrent_edit');
          }
        }
        for (final delta in op.balances) {
          final state = await _entity(txn, 'accounts', delta.account);
          final edited = op.edits
              .any((e) => e.table == 'accounts' && e.key == delta.account);
          if (!edited &&
              (state == null ||
                  state['deleted'] == 1 ||
                  state['revision'] != delta.accountRevision)) {
            throw const LedgerConflict('account_changed');
          }
        }
        for (final edit in op.edits) {
          final key = ledgerTables[edit.table];
          if (key == null) throw const LedgerConflict('unknown_table');
          final value = edit.value;
          if (value == null) {
            await txn
                .delete(edit.table, where: '$key = ?', whereArgs: [edit.key]);
          } else {
            final exists = (await txn.query(edit.table,
                    columns: [key], where: '$key = ?', whereArgs: [edit.key]))
                .isNotEmpty;
            if (exists) {
              await txn.update(edit.table, value,
                  where: '$key = ?', whereArgs: [edit.key]);
            } else {
              await txn.insert(
                  edit.table,
                  edit.table == 'accounts'
                      ? {...value, 'balance': 0.0}
                      : value);
            }
          }
          await _setEntity(txn, edit.table, edit.key, edit.baseRevision + 1,
              value == null ? null : await _hash(value));
        }
        for (final delta in op.balances) {
          await txn.rawUpdate(
              'UPDATE accounts SET balance = balance + ? WHERE id = ?',
              [delta.micros / 1e6, delta.account]);
        }
        await txn.insert('sync_applied', {'operation_id': op.id});
      }, scope: LedgerScope.remote);
}

class LedgerEdit {
  LedgerEdit(this.table, this.key, this.baseRevision, Map<String, Object?>? v)
      : _json = v == null ? null : canonicalSyncJson(v);
  final String table;
  final String key;
  final int baseRevision;
  final String? _json;
  Map<String, Object?>? get value =>
      _json == null ? null : jsonDecode(_json) as Map<String, Object?>;
  Map<String, Object?> toJson() => {
        'table': table,
        'key': key,
        'base_revision': baseRevision,
        'value': value,
      };
}

/// Exact integer change of an account balance, in millionths of the account
/// currency. [accountRevision] is the account entity revision it relied on:
/// renames or deletion elsewhere make it a conflict instead of an orphan.
class LedgerBalanceDelta {
  const LedgerBalanceDelta(this.account, this.micros, this.accountRevision);
  final String account;
  final int micros;
  final int accountRevision;
  Map<String, Object?> toJson() => {
        'account': account,
        'delta_micros': micros,
        'account_revision': accountRevision,
      };
}

class LedgerOperation {
  LedgerOperation({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.edits,
    required this.balances,
  });
  final String id;
  final String kind;
  final DateTime createdAt;
  final List<LedgerEdit> edits;
  final List<LedgerBalanceDelta> balances;

  String encode() => canonicalSyncJson({
        'format': ledgerJournalFormat,
        'id': id,
        'kind': kind,
        'created_at': createdAt.toIso8601String(),
        'edits': edits.map((e) => e.toJson()).toList(),
        'balances': balances.map((b) => b.toJson()).toList(),
      });

  factory LedgerOperation.decode(String encoded) {
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    if (json['format'] != ledgerJournalFormat) {
      throw const LedgerConflict('unsupported_format');
    }
    return LedgerOperation(
      id: json['id'] as String,
      kind: json['kind'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      edits: [
        for (final e in json['edits'] as List)
          LedgerEdit(e['table'] as String, e['key'] as String,
              e['base_revision'] as int, (e['value'] as Map?)?.cast())
      ],
      balances: [
        for (final b in json['balances'] as List)
          LedgerBalanceDelta(b['account'] as String, b['delta_micros'] as int,
              b['account_revision'] as int)
      ],
    );
  }
}
