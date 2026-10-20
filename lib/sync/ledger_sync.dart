import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'ledger_capture.dart';
import 'supabase_sync_transport.dart'
    show SyncAuthenticationRequired, SyncDeviceRevoked;
import 'sync_protocol.dart';

enum LedgerSyncStatus {
  idle,
  progressed,
  retryLater,
  conflict,

  /// A restore replaced the ledger; a new bootstrap is required.
  paused,

  /// Some write escaped a domain operation; nothing is sent until fixed.
  unattributed,
  authenticationRequired,
  deviceRevoked,
  busy,
}

/// A local operation the server could not accept as is. It was reverted
/// locally, so the device shows the same data as the others; the person's
/// alternative is kept here until discarded or reapplied.
class LedgerSyncConflict {
  LedgerSyncConflict(this.operation, this.reason, this.remote);
  final LedgerOperation operation;
  final String reason;

  /// Current values of the same entities (null = absent) when detected.
  final Map<String, Map<String, Object?>?> remote;

  /// Effect-free entities can be reapplied generically; anything that moves
  /// money must be redone through the normal screens and rules.
  bool get canReapply =>
      operation.balances.isEmpty &&
      operation.edits.every((e) => LedgerSync.reapplicable.contains(e.table));
}

/// Moves the ledger journal through a [SyncTransport]. Never invents data:
/// local state is always the server-ordered history plus unconfirmed local
/// operations replayed on top. Each received page is one SQLite commit.
class LedgerSync {
  LedgerSync(this.db, this.transport,
      {DateTime Function()? now, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random();

  final Database db;
  final SyncTransport transport;
  final DateTime Function() _now;
  final Random _random;
  bool _running = false;

  static const reapplicable = {
    'categories',
    'budgets',
    'wishlist',
    'assets',
    'lended_people',
    'import_rules',
  };

  static const _pageSize = 100;
  static const _checkpointEdits = 500;
  // The server refuses payloads above 1 MiB; real rows (notes, metadata)
  // vary in size, so a checkpoint operation is also bounded by bytes.
  static const checkpointBytes = 200 * 1024;

  static Future<void> _schema(DatabaseExecutor txn) async {
    await txn.execute('''CREATE TABLE IF NOT EXISTS sync_binding (
      singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
      dataset_id TEXT NOT NULL, epoch TEXT NOT NULL, device_id TEXT NOT NULL,
      cursor INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''');
    await txn.execute('''CREATE TABLE IF NOT EXISTS sync_conflicts (
      operation_id TEXT PRIMARY KEY, reason TEXT NOT NULL,
      remote_payload TEXT NOT NULL, created_at TEXT NOT NULL)''');
  }

  static void _validateIdentity(String dataset, String epoch, String device) {
    SyncKey(dataset, epoch).validate();
    SyncKey(device, device).validate();
  }

  /// First device: its current ledger becomes the dataset checkpoint. The
  /// checkpoint travels as ordinary operations (base revision 0), so the
  /// server and every later device see the same history.
  static Future<void> createDataset(Database db,
      {required String datasetId,
      required String epoch,
      required String deviceId}) async {
    _validateIdentity(datasetId, epoch, deviceId);
    if (await LedgerCapture.isInstalled(db)) {
      // Only an interrupted earlier attempt may continue: nothing journaled
      // and no binding yet, so the checkpoint still equals the installation.
      await db.transaction(_schema);
      if ((await db.query('sync_journal', limit: 1)).isNotEmpty ||
          (await db.query('sync_binding')).isNotEmpty) {
        throw StateError('Este banco já participa de um acervo.');
      }
    } else {
      await LedgerCapture.install(db);
    }
    await db.transaction((txn) async {
      await _schema(txn);
      final states = await txn.query('sync_entity_state',
          where: 'deleted = 0', orderBy: 'table_name, row_key');
      final byTable = <String, List<Map<String, Object?>>>{};
      for (final row in states) {
        (byTable[row['table_name'] as String] ??= []).add(row);
      }
      final balances = {
        for (final a in await txn.query('accounts'))
          a['id'] as String: ((a['balance'] as num) * 1e6).round()
      };
      var edits = <LedgerEdit>[];
      var effects = <LedgerBalanceDelta>[];
      var bytes = 0;
      Future<void> flush() async {
        if (edits.isEmpty) return;
        final op = LedgerOperation(
            id: const Uuid().v4(),
            kind: 'bootstrap.checkpoint',
            createdAt: DateTime.now().toUtc(),
            edits: edits,
            balances: effects);
        final payload = op.encode();
        await txn.insert('sync_journal', {
          'operation_id': op.id,
          'kind': op.kind,
          'payload': payload,
          'hash': '',
          'created_at': op.createdAt.toIso8601String(),
          'base_payload': canonicalSyncJson([
            for (final e in edits) LedgerEdit(e.table, e.key, 0, null).toJson()
          ]),
        });
        edits = [];
        effects = [];
        bytes = 0;
      }

      // Accounts first: every later operation may depend on them.
      for (final table in ['accounts', ...ledgerTables.keys]
          .toSet()
          .where(byTable.containsKey)) {
        for (final row in byTable[table]!) {
          final key = row['row_key'] as String;
          final json = row['value_json'] as String;
          if (edits.isNotEmpty && bytes + json.length > checkpointBytes) {
            await flush();
          }
          bytes += json.length + key.length;
          edits.add(LedgerEdit(
              table, key, 0, jsonDecode(json) as Map<String, Object?>));
          final micros = table == 'accounts' ? balances[key] ?? 0 : 0;
          if (micros != 0) effects.add(LedgerBalanceDelta(key, micros, 1));
          if (edits.length >= _checkpointEdits) await flush();
        }
      }
      await flush();
      await txn.insert('sync_binding', {
        'singleton': 1,
        'dataset_id': datasetId,
        'epoch': epoch,
        'device_id': deviceId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  static const _defaultCategories = {
    'food_exp', 'transport', 'shopping', 'bills', 'health', 'entertainment',
    'education', 'other_exp', 'salary', 'freelance', 'business', 'investment',
    'gift', //
  };

  /// A second device joins an existing dataset only from an empty ledger.
  /// It never merges by names or values; a device with its own data must be
  /// handled by an explicit decision, not here.
  static Future<void> joinDataset(Database db,
      {required String datasetId,
      required String epoch,
      required String deviceId}) async {
    _validateIdentity(datasetId, epoch, deviceId);
    if (await LedgerCapture.isInstalled(db)) {
      throw StateError('Este banco já participa de outro acervo.');
    }
    await db.transaction((txn) async {
      for (final table in ledgerTables.keys) {
        if (table == 'accounts' || table == 'categories') continue;
        if ((await txn.query(table, limit: 1)).isNotEmpty) {
          throw StateError(
              'Este aparelho já tem lançamentos. Escolha qual acervo manter antes de entrar.');
        }
      }
      final accounts = await txn.query('accounts');
      final custom = await txn.query('categories');
      if (accounts.any((a) => (a['balance'] as num) != 0) ||
          custom.any((c) => !_defaultCategories.contains(c['id']))) {
        throw StateError(
            'Este aparelho já tem contas ou categorias próprias. Escolha qual acervo manter antes de entrar.');
      }
      // Only untouched defaults remain; the dataset brings its own.
      await txn.delete('accounts');
      await txn.delete('categories');
    });
    await LedgerCapture.install(db);
    await db.transaction((txn) async {
      await _schema(txn);
      await txn.insert('sync_binding', {
        'singleton': 1,
        'dataset_id': datasetId,
        'epoch': epoch,
        'device_id': deviceId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    });
  }

  Future<Map<String, Object?>> _binding(DatabaseExecutor txn) async {
    final rows = await txn.query('sync_binding');
    if (rows.isEmpty) throw StateError('Sincronização não configurada.');
    return rows.single;
  }

  Future<int> get cursor async => (await _binding(db))['cursor'] as int;

  Future<int> get pendingCount async => Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM sync_journal WHERE state IN ('pending', 'accepted')"))!;

  SyncOperation _toSync(LedgerOperation op, Map<String, Object?> binding) {
    final edited = {
      for (final e in op.edits)
        if (e.table == 'accounts') e.key
    };
    return SyncOperation(
      id: op.id,
      datasetId: binding['dataset_id'] as String,
      epoch: binding['epoch'] as String,
      deviceId: binding['device_id'] as String,
      createdAt: op.createdAt,
      edits: [
        for (final e in op.edits)
          SyncEdit(SyncKey(e.table, e.key), e.baseRevision, e.value)
      ],
      effects: [for (final b in op.balances) SyncEffect(b.account, b.micros)],
      requires: [
        for (final b in op.balances)
          if (!edited.contains(b.account))
            SyncRequirement(SyncKey('accounts', b.account), b.accountRevision)
      ],
      label: op.kind,
    );
  }

  static LedgerOperation _fromSync(SyncOperation op) {
    for (final key in op.checkedKeys) {
      if (!ledgerTables.containsKey(key.kind)) {
        throw const LedgerConflict('unknown_table');
      }
    }
    final required = {
      for (final r in op.requires)
        if (r.key.kind == 'accounts') r.key.id: r.revision
    };
    final edited = {
      for (final e in op.edits)
        if (e.key.kind == 'accounts') e.key.id: e.baseRevision + 1
    };
    return LedgerOperation(
      id: op.id,
      kind: op.label ?? 'remote',
      createdAt: op.createdAt,
      edits: [
        for (final e in op.edits)
          LedgerEdit(e.key.kind, e.key.id, e.baseRevision, e.value)
      ],
      balances: [
        for (final effect in op.effects)
          LedgerBalanceDelta(
              effect.account,
              effect.deltaMicros,
              edited[effect.account] ??
                  required[effect.account] ??
                  (throw const LedgerConflict('effect_without_requirement'))),
      ],
    );
  }

  Future<LedgerSyncStatus> synchronize({int maxPages = 20}) async {
    if (_running) return LedgerSyncStatus.busy;
    _running = true;
    try {
      final binding = await _binding(db);
      if (await LedgerCapture.restoreBarrier(db))
        return LedgerSyncStatus.paused;
      if (await LedgerCapture.unattributedChanges(db) > 0) {
        return LedgerSyncStatus.unattributed;
      }
      var progressed = false;
      var retry = false;
      try {
        final pushed = await _push(binding);
        // Waiting to resend must not stop receiving the other devices' work.
        retry = pushed == null;
        progressed |= pushed ?? false;
        for (var page = 0; page < maxPages; page++) {
          final received = await _pull(binding);
          if (received == 0) break;
          progressed = true;
        }
        if (await _settleRejected()) progressed = true;
        // Operations rebased onto newer remote data may now be sendable.
        if (progressed && (await _push(binding) ?? false)) {
          await _pull(binding);
        }
      } on SyncUnavailable {
        return LedgerSyncStatus.retryLater;
      } on SyncAuthenticationRequired {
        return LedgerSyncStatus.authenticationRequired;
      } on SyncDeviceRevoked {
        return LedgerSyncStatus.deviceRevoked;
      }
      if ((await db.query('sync_conflicts', limit: 1)).isNotEmpty) {
        return LedgerSyncStatus.conflict;
      }
      if (retry && await pendingCount > 0) return LedgerSyncStatus.retryLater;
      return progressed ? LedgerSyncStatus.progressed : LedgerSyncStatus.idle;
    } finally {
      _running = false;
    }
  }

  /// Returns null when the network is unavailable (retry later), otherwise
  /// whether anything was accepted. Stops at the first rejection: the pull
  /// that follows brings the remote change it collided with.
  Future<bool?> _push(Map<String, Object?> binding) async {
    var progressed = false;
    final rows = await db.query('sync_journal',
        where: "state = 'pending' AND rejected = 0", orderBy: 'position');
    for (final row in rows) {
      if ((row['next_retry_at'] as int) > _now().millisecondsSinceEpoch) {
        return progressed ? true : null;
      }
      final op =
          _toSync(LedgerOperation.decode(row['payload'] as String), binding);
      final SyncPushResult result;
      try {
        result = await transport.push(op);
      } on SyncUnavailable {
        final attempts = (row['attempts'] as int) + 1;
        final seconds = min(300, 1 << min(attempts, 8));
        await db.update(
            'sync_journal',
            {
              'attempts': attempts,
              'next_retry_at': _now().millisecondsSinceEpoch +
                  seconds * 1000 +
                  _random.nextInt(seconds * 250 + 1),
            },
            where: 'operation_id = ?',
            whereArgs: [op.id]);
        return progressed ? true : null;
      }
      if (result is SyncRejected) {
        await db.update('sync_journal', {'rejected': 1},
            where: 'operation_id = ?', whereArgs: [op.id]);
        break;
      }
      final receipt = (result as SyncAccepted).receipt;
      await receipt.validate();
      requireSync(
          receipt.operation.id == op.id && receipt.hash == await op.digest(),
          'receipt_mismatch');
      await db.update('sync_journal',
          {'state': 'accepted', 'server_revision': receipt.revision},
          where: "operation_id = ? AND state = 'pending'", whereArgs: [op.id]);
      progressed = true;
    }
    return progressed;
  }

  Future<
      List<
          ({
            LedgerOperation op,
            List<LedgerEdit> base,
            bool accepted,
            bool rejected
          })>> _unconfirmed(DatabaseExecutor txn) async => [
        for (final row in await txn.query('sync_journal',
            where: "state IN ('pending', 'accepted')", orderBy: 'position'))
          (
            op: LedgerOperation.decode(row['payload'] as String),
            base: LedgerCapture.decodeBase(row['base_payload'] as String),
            accepted: row['state'] == 'accepted',
            rejected: row['rejected'] == 1,
          )
      ];

  Future<Map<String, Map<String, Object?>?>> _current(
      DatabaseExecutor txn, LedgerOperation op) async {
    final result = <String, Map<String, Object?>?>{};
    for (final e in op.edits) {
      final rows = await txn.query(e.table,
          where: '${ledgerTables[e.table]} = ?', whereArgs: [e.key]);
      result['${e.table}/${e.key}'] =
          rows.isEmpty ? null : LedgerCapture.value(e.table, rows.single);
    }
    return result;
  }

  Future<void> _conflict(
      DatabaseExecutor txn, LedgerOperation op, String reason) async {
    await txn.update('sync_journal', {'state': 'conflict'},
        where: 'operation_id = ?', whereArgs: [op.id]);
    await txn.insert(
        'sync_conflicts',
        {
          'operation_id': op.id,
          'reason': reason,
          'remote_payload': canonicalSyncJson(await _current(txn, op)),
          'created_at': _now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Re-applies unconfirmed operations after [received] changed the history
  /// beneath them. Operations that no longer fit become conflicts.
  Future<void> _replay(
      DatabaseExecutor txn,
      List<
              ({
                LedgerOperation op,
                List<LedgerEdit> base,
                bool accepted,
                bool rejected
              })>
          pending) async {
    for (final item in pending) {
      if (item.rejected) {
        await _conflict(txn, item.op, 'server_rejected');
        continue;
      }
      try {
        await LedgerCapture.applyIn(txn, item.op);
      } on LedgerConflict catch (e) {
        // The server accepted it after everything received so far.
        if (item.accepted) throw StateError('accepted_operation_conflict');
        await _conflict(txn, item.op, e.code);
      }
    }
  }

  Future<int> _pull(Map<String, Object?> binding) async {
    final after = await cursor;
    final page = await transport.pull(
        datasetId: binding['dataset_id'] as String,
        epoch: binding['epoch'] as String,
        after: after,
        limit: _pageSize);
    if (page.isEmpty) return 0;
    for (final receipt in page) {
      await receipt.validate();
    }
    await ledgerTransaction(db, 'sync.pull', (txn) async {
      if (await LedgerCapture.restoreBarrier(txn)) {
        throw const LedgerConflict('restore_review_required');
      }
      var position = (await _binding(txn))['cursor'] as int;
      requireSync(position == after, 'concurrent_pull');
      final pending = await _unconfirmed(txn);
      var reverted = false;
      for (final receipt in page) {
        requireSync(receipt.revision == position + 1, 'cursor_gap');
        final remote = receipt.operation;
        requireSync(
            remote.datasetId == binding['dataset_id'] &&
                remote.epoch == binding['epoch'],
            'wrong_dataset_or_epoch');
        final own = remote.deviceId == binding['device_id'] &&
            pending.isNotEmpty &&
            pending.first.op.id == remote.id;
        if (own) {
          final item = pending.removeAt(0);
          requireSync(await _toSync(item.op, binding).digest() == receipt.hash,
              'receipt_mismatch');
          // Already applied locally unless it was set aside for a rebase.
          if (reverted) await LedgerCapture.applyIn(txn, item.op);
          await txn.update('sync_journal',
              {'state': 'confirmed', 'server_revision': receipt.revision},
              where: 'operation_id = ?', whereArgs: [item.op.id]);
        } else {
          requireSync(
              (await txn.query('sync_journal',
                      where: 'operation_id = ?', whereArgs: [remote.id]))
                  .isEmpty,
              'own_operation_out_of_order');
          if (!reverted && pending.isNotEmpty) {
            for (final item in pending.reversed) {
              await LedgerCapture.revertIn(txn, item.op, item.base);
            }
            reverted = true;
          }
          // A server-accepted operation must fit the server-ordered state.
          await LedgerCapture.applyIn(txn, _fromSync(remote));
          await txn.insert('sync_applied', {'operation_id': remote.id},
              conflictAlgorithm: ConflictAlgorithm.ignore);
        }
        position = receipt.revision;
      }
      if (reverted) await _replay(txn, pending);
      await txn.update('sync_binding', {'cursor': position});
    }, scope: LedgerScope.remote);
    return page.length;
  }

  /// A rejected operation whose colliding change has already been received
  /// (or never will be) is set aside so the queue cannot stall forever.
  Future<bool> _settleRejected() async {
    final pending = await _unconfirmed(db);
    if (!pending.any((p) => p.rejected)) return false;
    await ledgerTransaction(db, 'sync.settle', (txn) async {
      for (final item in pending.reversed) {
        await LedgerCapture.revertIn(txn, item.op, item.base);
      }
      await _replay(txn, pending);
    }, scope: LedgerScope.remote);
    return true;
  }

  Future<List<LedgerSyncConflict>> conflicts() async {
    final rows = await db.rawQuery(
        'SELECT c.reason, c.remote_payload, j.payload FROM sync_conflicts c '
        'JOIN sync_journal j ON j.operation_id = c.operation_id '
        'ORDER BY j.position');
    return [
      for (final r in rows)
        LedgerSyncConflict(
            LedgerOperation.decode(r['payload'] as String),
            r['reason'] as String,
            (jsonDecode(r['remote_payload'] as String) as Map)
                .map((k, v) => MapEntry(k as String, (v as Map?)?.cast())))
    ];
  }

  /// Keeps the other devices' version. The local alternative is already
  /// reverted; the journal keeps it as history.
  Future<void> discard(String operationId) => db.transaction((txn) async {
        await txn.update('sync_journal', {'state': 'discarded'},
            where: "operation_id = ? AND state = 'conflict'",
            whereArgs: [operationId]);
        await txn.delete('sync_conflicts',
            where: 'operation_id = ?', whereArgs: [operationId]);
      });

  /// Writes the local alternative again on top of the current data, as a new
  /// operation with current revisions. Only for effect-free entities.
  Future<void> reapply(String operationId) async {
    final conflict = (await conflicts())
        .where((c) => c.operation.id == operationId)
        .firstOrNull;
    if (conflict == null) throw StateError('Conflito não encontrado.');
    if (!conflict.canReapply) {
      throw StateError(
          'Esta alteração mexe em dinheiro. Refaça pelo app para recalcular os saldos.');
    }
    await ledgerTransaction(db, 'sync.reapply', (txn) async {
      for (final edit in conflict.operation.edits) {
        final column = ledgerTables[edit.table]!;
        final value = edit.value;
        if (value == null) {
          await txn
              .delete(edit.table, where: '$column = ?', whereArgs: [edit.key]);
        } else if ((await txn
                .query(edit.table, where: '$column = ?', whereArgs: [edit.key]))
            .isEmpty) {
          await txn.insert(edit.table, value);
        } else {
          await txn.update(edit.table, value,
              where: '$column = ?', whereArgs: [edit.key]);
        }
      }
      await txn.update('sync_journal', {'state': 'resolved'},
          where: 'operation_id = ?', whereArgs: [operationId]);
      await txn.delete('sync_conflicts',
          where: 'operation_id = ?', whereArgs: [operationId]);
    });
  }
}
