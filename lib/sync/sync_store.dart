import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'sync_protocol.dart';

enum SyncPass { idle, progressed, retryLater, conflict, paused, busy }

/// Isolated, opt-in synchronization journal for synthetic validation only.
/// Does NOT open DBHelper, install a production migration, or copy SQLite files.
/// A domain adapter + authenticated transport + conflict UX are still required.
class SyncStore {
  SyncStore(this.db, {DateTime Function()? now, Random? random})
      : _now = now ?? DateTime.now,
        _random = random ?? Random();

  final Database db;
  final DateTime Function() _now;
  final Random _random;
  bool _running = false;

  Future<void> initialize({
    required String datasetId,
    required String epoch,
    required String deviceId,
  }) async {
    SyncKey(datasetId, epoch).validate();
    SyncKey(deviceId, deviceId).validate();
    await db.transaction((tx) async {
      await tx.execute('''CREATE TABLE IF NOT EXISTS sync_lab_binding (
        singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
        schema_version INTEGER NOT NULL DEFAULT 1,
        dataset_id TEXT NOT NULL, epoch TEXT NOT NULL, device_id TEXT NOT NULL,
        cursor INTEGER NOT NULL DEFAULT 0, paused INTEGER NOT NULL DEFAULT 0)''');
      await tx.execute('''CREATE TABLE IF NOT EXISTS sync_lab_entities (
        kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL,
        value_json TEXT, updated_at TEXT NOT NULL, deleted_at TEXT,
        device_id TEXT NOT NULL, PRIMARY KEY(kind, id))''');
      await tx.execute('''CREATE TABLE IF NOT EXISTS sync_lab_outbox (
        position INTEGER PRIMARY KEY AUTOINCREMENT, id TEXT UNIQUE NOT NULL,
        payload TEXT NOT NULL, base_payload TEXT NOT NULL,
        hash TEXT NOT NULL, state TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0, next_retry_at INTEGER NOT NULL DEFAULT 0)''');
      await tx.execute('''CREATE TABLE IF NOT EXISTS sync_lab_applied (
        id TEXT PRIMARY KEY, hash TEXT NOT NULL, revision INTEGER UNIQUE NOT NULL)''');
      await tx.execute('''CREATE TABLE IF NOT EXISTS sync_lab_conflicts (
        id TEXT PRIMARY KEY, local_payload TEXT NOT NULL,
        base_payload TEXT NOT NULL, remote_payload TEXT NOT NULL,
        reason TEXT NOT NULL, created_at TEXT NOT NULL)''');
      final existing = await tx.query('sync_lab_binding');
      if (existing.isEmpty) {
        await tx.insert('sync_lab_binding', {
          'singleton': 1,
          'dataset_id': datasetId,
          'epoch': epoch,
          'device_id': deviceId,
        });
      } else {
        final binding = existing.single;
        requireSync(
            binding['schema_version'] == 1, 'unsupported_journal_schema');
        requireSync(
            binding['dataset_id'] == datasetId &&
                binding['epoch'] == epoch &&
                binding['device_id'] == deviceId,
            'binding_mismatch');
      }
    });
  }

  Future<Map<String, Object?>> _binding(DatabaseExecutor tx) async =>
      (await tx.query('sync_lab_binding')).single;

  Future<Map<String, Object?>?> _entity(
      DatabaseExecutor tx, SyncKey key) async {
    final rows = await tx.query('sync_lab_entities',
        where: 'kind = ? AND id = ?', whereArgs: [key.kind, key.id]);
    return rows.isEmpty ? null : rows.single;
  }

  Future<int> revision(SyncKey key) async =>
      ((await _entity(db, key))?['revision'] as int?) ?? 0;

  Future<Map<String, dynamic>?> value(SyncKey key) async {
    final encoded = (await _entity(db, key))?['value_json'] as String?;
    return encoded == null ? null : jsonDecode(encoded) as Map<String, dynamic>;
  }

  Future<int> get cursor async => (await _binding(db))['cursor'] as int;
  Future<int> get pendingCount async => Sqflite.firstIntValue(await db.rawQuery(
      "SELECT COUNT(*) FROM sync_lab_outbox WHERE state != 'accepted'"))!;
  Future<List<Map<String, Object?>>> get conflicts =>
      db.query('sync_lab_conflicts', orderBy: 'created_at, id');

  /// Local projection and durable outbox are one SQLite commit. Local work
  /// remains possible offline or after the restore barrier; network stays paused.
  Future<SyncOperation> stage(List<SyncEdit> edits,
      {String? operationId}) async {
    return db.transaction((tx) async {
      final binding = await _binding(tx);
      final operation = SyncOperation(
        id: operationId ?? const Uuid().v4(),
        datasetId: binding['dataset_id'] as String,
        epoch: binding['epoch'] as String,
        deviceId: binding['device_id'] as String,
        createdAt: _now(),
        edits: edits,
      );
      final base = <Map<String, dynamic>>[];
      for (final edit in edits) {
        final current = await _entity(tx, edit.key);
        requireSync((current?['revision'] ?? 0) == edit.baseRevision,
            'stale_local_edit');
        final encoded = current?['value_json'] as String?;
        base.add({
          ...edit.key.toJson(),
          'revision': edit.baseRevision,
          'value': encoded == null ? null : jsonDecode(encoded),
        });
      }
      await _apply(tx, operation);
      await tx.insert('sync_lab_outbox', {
        'id': operation.id,
        'payload': operation.encode(),
        'base_payload': canonicalSyncJson(base),
        'hash': await operation.digest(),
        'state': 'pending',
      });
      return operation;
    });
  }

  Future<void> _apply(DatabaseExecutor tx, SyncOperation operation) async {
    for (final edit in operation.edits) {
      await tx.insert(
          'sync_lab_entities',
          {
            'kind': edit.key.kind,
            'id': edit.key.id,
            'revision': edit.baseRevision + 1,
            'value_json': edit.deleted ? null : canonicalSyncJson(edit.value),
            'updated_at': operation.createdAt.toIso8601String(),
            'deleted_at':
                edit.deleted ? operation.createdAt.toIso8601String() : null,
            'device_id': operation.deviceId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  void _checkBinding(Map<String, Object?> binding, SyncOperation operation) {
    requireSync(
        operation.datasetId == binding['dataset_id'] &&
            operation.epoch == binding['epoch'],
        'wrong_dataset_or_epoch');
  }

  Future<void> _ack(DatabaseExecutor tx, SyncReceipt receipt) async {
    final previous = await tx.query('sync_lab_applied',
        where: 'id = ?', whereArgs: [receipt.operation.id]);
    if (previous.isNotEmpty) {
      requireSync(
          previous.single['hash'] == receipt.hash &&
              previous.single['revision'] == receipt.revision,
          'receipt_mismatch');
      return;
    }
    await tx.insert('sync_lab_applied', {
      'id': receipt.operation.id,
      'hash': receipt.hash,
      'revision': receipt.revision,
    });
  }

  Future<void> _conflict(DatabaseExecutor tx, SyncOperation local,
      Object remote, String reason) async {
    final outbox = (await tx
            .query('sync_lab_outbox', where: 'id = ?', whereArgs: [local.id]))
        .single;
    await tx.insert(
        'sync_lab_conflicts',
        {
          'id': local.id,
          'local_payload': local.encode(),
          'base_payload': outbox['base_payload'],
          'remote_payload': canonicalSyncJson(remote),
          'reason': reason,
          'created_at': _now().toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore);
    await tx.update('sync_lab_outbox', {'state': 'conflict'},
        where: 'id = ?', whereArgs: [local.id]);
  }

  /// One atomic aggregate per cursor step; earlier committed steps may survive
  /// a later failed step. Neither half a transfer nor a skipped cursor can.
  Future<bool> accept(SyncReceipt receipt) async {
    await receipt.validate();
    return db.transaction((tx) async {
      final binding = await _binding(tx);
      _checkBinding(binding, receipt.operation);
      requireSync(binding['paused'] == 0, 'restore_review_required');
      final currentCursor = binding['cursor'] as int;
      final known = await tx.query('sync_lab_applied',
          where: 'id = ?', whereArgs: [receipt.operation.id]);
      if (known.isNotEmpty) {
        requireSync(
            known.single['hash'] == receipt.hash &&
                known.single['revision'] == receipt.revision,
            'receipt_mismatch');
      }
      if (receipt.revision <= currentCursor) {
        requireSync(known.isNotEmpty, 'unknown_old_receipt');
        return true;
      }
      requireSync(receipt.revision == currentCursor + 1, 'cursor_gap');
      if (known.isEmpty) {
        final pending = await tx.query('sync_lab_outbox',
            where: "state != 'accepted'", orderBy: 'position');
        // A lost push response may be delivered by pull. A matching operation
        // already affected the local projection and must not be applied twice.
        final own = pending.where((r) => r['id'] == receipt.operation.id);
        if (own.isNotEmpty) {
          requireSync(own.single['hash'] == receipt.hash, 'receipt_mismatch');
          await tx.update('sync_lab_outbox', {'state': 'accepted'},
              where: 'id = ?', whereArgs: [receipt.operation.id]);
        } else {
          final changed = receipt.operation.edits.map((e) => e.key).toSet();
          for (final row in pending) {
            final local = SyncOperation.decode(row['payload'] as String);
            if (local.edits.any((edit) => changed.contains(edit.key))) {
              await _conflict(tx, local, receipt.toJson(), 'concurrent_edit');
              return false;
            }
          }
          for (final edit in receipt.operation.edits) {
            final entity = await _entity(tx, edit.key);
            requireSync((entity?['revision'] ?? 0) == edit.baseRevision,
                'projection_revision_mismatch');
          }
          await _apply(tx, receipt.operation);
        }
        await _ack(tx, receipt);
      }
      await tx.update('sync_lab_binding', {'cursor': receipt.revision},
          where: 'singleton = 1');
      return true;
    });
  }

  Future<SyncPass> synchronize(SyncTransport transport) async {
    if (_running) return SyncPass.busy;
    _running = true;
    try {
      final binding = await _binding(db);
      if (binding['paused'] == 1) return SyncPass.paused;
      var progressed = false;
      // Bound each pass: a backlog must not occupy the app indefinitely.
      for (var count = 0; count < 100; count++) {
        if ((await _binding(db))['paused'] == 1) return SyncPass.paused;
        final rows = await db.query('sync_lab_outbox',
            where: "state != 'accepted'", orderBy: 'position', limit: 1);
        if (rows.isEmpty) break;
        final row = rows.single;
        if (row['state'] == 'conflict') return SyncPass.conflict;
        if ((row['next_retry_at'] as int) > _now().millisecondsSinceEpoch) {
          return SyncPass.retryLater;
        }
        final operation = SyncOperation.decode(row['payload'] as String);
        _checkBinding(binding, operation);
        requireSync(row['hash'] == await operation.digest(), 'outbox_corrupt');
        SyncPushResult result;
        try {
          result = await transport.push(operation);
        } on SyncUnavailable {
          final attempts = (row['attempts'] as int) + 1;
          final seconds = min(300, 1 << min(attempts, 8));
          final jitter = _random.nextInt(seconds * 250 + 1);
          await db.update(
              'sync_lab_outbox',
              {
                'attempts': attempts,
                'next_retry_at':
                    _now().millisecondsSinceEpoch + seconds * 1000 + jitter,
              },
              where: 'id = ?',
              whereArgs: [operation.id]);
          return SyncPass.retryLater;
        }
        if (result is SyncRejected) {
          requireSync(
              result.remote.length == operation.checkedKeys.length &&
                  result.remote
                      .map((r) => r.key)
                      .toSet()
                      .containsAll(operation.checkedKeys),
              'incomplete_remote_alternative');
          final remote = result.remote.map((e) => e.toJson()).toList();
          await db.transaction(
              (tx) => _conflict(tx, operation, remote, 'revision_conflict'));
          return SyncPass.conflict;
        }
        final receipt = (result as SyncAccepted).receipt;
        await receipt.validate();
        requireSync(
            receipt.operation.id == operation.id && receipt.hash == row['hash'],
            'receipt_mismatch');
        await db.transaction((tx) async {
          requireSync(
              (await _binding(tx))['paused'] == 0, 'restore_review_required');
          await _ack(tx, receipt);
          await tx.update('sync_lab_outbox', {'state': 'accepted'},
              where: 'id = ?', whereArgs: [operation.id]);
        });
        progressed = true;
      }
      List<SyncReceipt> page;
      if ((await _binding(db))['paused'] == 1) return SyncPass.paused;
      try {
        page = await transport.pull(
            datasetId: binding['dataset_id'] as String,
            epoch: binding['epoch'] as String,
            after: await cursor,
            limit: 100);
      } on SyncUnavailable {
        return SyncPass.retryLater;
      }
      requireSync(page.length <= 100, 'page_too_big');
      for (final receipt in page) {
        if (!await accept(receipt)) return SyncPass.conflict;
        progressed = true;
      }
      return progressed ? SyncPass.progressed : SyncPass.idle;
    } finally {
      _running = false;
    }
  }

  /// This is only the journal barrier. Production restore still needs to call
  /// it before touching any ledger row and preserve a recoverable local copy.
  /// No automatic resume exists: an old backup must not recreate deleted money.
  Future<void> pauseForRestore() async {
    await db.update('sync_lab_binding', {'paused': 1}, where: 'singleton = 1');
  }
}
