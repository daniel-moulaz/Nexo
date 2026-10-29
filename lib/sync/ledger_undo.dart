import 'package:sqflite/sqflite.dart';

import 'ledger_capture.dart';
import 'sync_protocol.dart' show canonicalSyncJson;

/// Undo of what one assistant request changed, built from the sync journal
/// of the operations the request committed. It travels with the request
/// (the server keeps it in the result), so any device of the person can undo
/// it later. Undoing is itself one user operation: it syncs like any other.
///
/// The undo only applies when every row is still exactly as the request
/// left it; otherwise nothing changes and the person is told to fix it in
/// the app. Balances move back by the exact deltas the request recorded.
abstract final class LedgerUndo {
  static const format = 1;

  /// A request that touched more than this is not undone automatically.
  static const maxBytes = 200 * 1024;

  /// Null when nothing was journaled (sync not active on this device).
  static Future<Map<String, Object?>?> capture(
      Database db, List<String> operationIds) async {
    if (operationIds.isEmpty || !await LedgerCapture.isInstalled(db)) {
      return null;
    }
    final rows = await db.query('sync_journal',
        where:
            'operation_id IN (${List.filled(operationIds.length, '?').join(', ')})',
        whereArgs: operationIds,
        orderBy: 'position');
    if (rows.isEmpty) return null;
    final order = <String>[];
    final before = <String, Map<String, Object?>?>{};
    final after = <String, Map<String, Object?>?>{};
    final tables = <String, (String, String)>{};
    final balances = <String, int>{};
    for (final row in rows) {
      final op = LedgerOperation.decode(row['payload'] as String);
      final base = {
        for (final b in LedgerCapture.decodeBase(row['base_payload'] as String))
          _key(b.table, b.key): b.value
      };
      for (final e in op.edits) {
        final k = _key(e.table, e.key);
        if (!tables.containsKey(k)) {
          tables[k] = (e.table, e.key);
          order.add(k);
          before[k] = base[k];
        }
        after[k] = e.value;
      }
      for (final b in op.balances) {
        balances.update(b.account, (v) => v + b.micros,
            ifAbsent: () => b.micros);
      }
    }
    final blob = <String, Object?>{
      'format': format,
      'entities': [
        for (final k in order)
          if (!_same(before[k], after[k]))
            {
              'table': tables[k]!.$1,
              'key': tables[k]!.$2,
              'before': before[k],
              'after': after[k],
            }
      ],
      'balances': [
        for (final e in balances.entries)
          if (e.value != 0) {'account': e.key, 'micros': e.value}
      ],
    };
    if (canonicalSyncJson(blob).length > maxBytes) {
      return {'format': format, 'too_large': true};
    }
    return blob;
  }

  /// Whether [blob] can be applied at all (shape, not current data).
  static bool usable(Object? blob) =>
      blob is Map &&
      blob['format'] == format &&
      blob['too_large'] != true &&
      blob['entities'] is List &&
      blob['balances'] is List;

  /// Applies [blob] as one operation named `assistant.undo`.
  static Future<void> apply(Database db, Map<String, Object?> blob) async {
    if (!await LedgerCapture.isInstalled(db)) {
      throw StateError(
          'Desfazer precisa da sincronização ativa neste aparelho.');
    }
    if (blob['too_large'] == true) {
      throw StateError(
          'Este pedido mexeu em dados demais para desfazer sozinho. Desfaça pelo app.');
    }
    if (!usable(blob)) {
      throw StateError('Os dados para desfazer este pedido estão incompletos.');
    }
    final entities = [
      for (final e in blob['entities'] as List)
        (e as Map).cast<String, Object?>()
    ];
    final balances = [
      for (final b in blob['balances'] as List)
        (b as Map).cast<String, Object?>()
    ];
    await ledgerTransaction(db, 'assistant.undo', (txn) async {
      for (final e in entities) {
        final table = e['table'] as String;
        final column = ledgerTables[table];
        if (column == null) {
          throw StateError('Pedido de uma versão diferente do app.');
        }
        final rows =
            await txn.query(table, where: '$column = ?', whereArgs: [e['key']]);
        final current =
            rows.isEmpty ? null : LedgerCapture.value(table, rows.single);
        if (!_same(current, _map(e['after']))) {
          throw StateError(
              '${_label(table)} mudou depois do pedido. Nada foi desfeito; ajuste pelo app.');
        }
      }
      // Accounts the request created disappear with their balance; accounts
      // it removed come back at zero and then receive their money back.
      final created = {
        for (final e in entities)
          if (e['table'] == 'accounts' && e['before'] == null) e['key']
      };
      for (final e in entities.reversed) {
        await LedgerCapture.writeRow(
            txn, e['table'] as String, e['key'] as String, _map(e['before']));
      }
      for (final b in balances) {
        if (created.contains(b['account'])) continue;
        final changed = await txn.rawUpdate(
            'UPDATE accounts SET balance = balance - ? WHERE id = ?',
            [(b['micros'] as num).toInt() / 1e6, b['account']]);
        if (changed != 1) {
          throw StateError(
              'Uma conta do pedido não existe mais. Nada foi desfeito.');
        }
      }
    });
  }

  static String _key(String table, String key) => '$table\u0000$key';

  static Map<String, Object?>? _map(Object? v) =>
      v == null ? null : (v as Map).cast<String, Object?>();

  /// Deep equality where numbers compare by value (JSON and SQLite may
  /// disagree on 32 versus 32.0).
  static bool _same(Object? a, Object? b) {
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_same(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_same(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static String _label(String table) => switch (table) {
        'accounts' => 'Uma conta',
        'categories' => 'Uma categoria',
        'transactions' || 'transaction_metadata' => 'Um lançamento',
        'recurring_payments' || 'recurring_history' => 'Uma recorrente',
        'budgets' => 'Um orçamento',
        'savings_goals' || 'savings_contributions' => 'Um objetivo',
        'investments' || 'investment_operations' => 'Um investimento',
        'loans' || 'loan_payments' => 'Um empréstimo',
        'lended_money' || 'lended_people' => 'Um empréstimo pessoal',
        'shared_settings' => 'Uma configuração',
        _ => 'Um registro',
      };
}
