import 'dart:convert';

import 'sync_protocol.dart';
import 'package:sqflite/sqflite.dart';

/// Transactional in-process reference server: tests and the on-device
/// rehearsal before activation. No HTTP, authentication, RLS,
/// encryption or real hosting is implied by the local protocol tests.
class SqliteSyncServer implements SyncTransport {
  SqliteSyncServer(this.db, this.datasetId, this.epoch);
  final Database db;
  final String datasetId;
  final String epoch;
  bool offline = false;
  bool loseNextResponse = false;
  int pushes = 0;

  Future<void> initialize() async {
    await db.execute('''CREATE TABLE server_clock (
      singleton INTEGER PRIMARY KEY, revision INTEGER NOT NULL)''');
    await db.insert('server_clock', {'singleton': 1, 'revision': 0});
    await db.execute('''CREATE TABLE server_entities (
      kind TEXT NOT NULL, id TEXT NOT NULL, revision INTEGER NOT NULL,
      value_json TEXT, PRIMARY KEY(kind, id))''');
    await db.execute('''CREATE TABLE server_requests (
      id TEXT PRIMARY KEY, hash TEXT NOT NULL, receipt TEXT, rejected TEXT)''');
    await db.execute('''CREATE TABLE server_log (
      revision INTEGER PRIMARY KEY, payload TEXT NOT NULL, hash TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE server_balances (
      account TEXT PRIMARY KEY, micros INTEGER NOT NULL)''');
  }

  /// Read projection of protocol-2 effects, as a server API would expose it.
  Future<int> balanceMicros(String account) async =>
      ((await db.query('server_balances',
              where: 'account = ?', whereArgs: [account]))
          .firstOrNull?['micros'] as int?) ??
      0;

  Future<int> get revision async =>
      (await db.query('server_clock')).single['revision'] as int;

  void _binding(String dataset, String candidateEpoch) => requireSync(
      dataset == datasetId && candidateEpoch == epoch,
      'wrong_dataset_or_epoch');

  SyncReceipt _receipt(Map<String, dynamic> json) => SyncReceipt(
      json['revision'] as int,
      SyncOperation.decode(jsonEncode(json['operation'])),
      json['hash'] as String);

  SyncRejected _rejected(String encoded) =>
      SyncRejected((jsonDecode(encoded) as List)
          .map((r) => SyncRemoteState(
              SyncKey(r['kind'] as String, r['id'] as String),
              r['revision'] as int,
              (r['value'] as Map?)?.cast<String, dynamic>()))
          .toList());

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    pushes++;
    if (offline) throw const SyncUnavailable();
    _binding(operation.datasetId, operation.epoch);
    final hash = await operation.digest();
    final result = await db.transaction<SyncPushResult>((tx) async {
      final prior = await tx
          .query('server_requests', where: 'id = ?', whereArgs: [operation.id]);
      if (prior.isNotEmpty) {
        requireSync(prior.single['hash'] == hash, 'operation_id_reused');
        final encoded = prior.single['receipt'] as String?;
        return encoded == null
            ? _rejected(prior.single['rejected'] as String)
            : SyncAccepted(_receipt(jsonDecode(encoded)));
      }
      final remote = <SyncRemoteState>[];
      var mismatch = false;
      final expected = {
        for (final edit in operation.edits) edit.key: edit.baseRevision,
        for (final need in operation.requires) need.key: need.revision,
      };
      for (final entry in expected.entries) {
        final rows = await tx.query('server_entities',
            where: 'kind = ? AND id = ?',
            whereArgs: [entry.key.kind, entry.key.id]);
        final revision = rows.isEmpty ? 0 : rows.single['revision'] as int;
        final json = rows.isEmpty ? null : rows.single['value_json'] as String?;
        remote.add(SyncRemoteState(
            entry.key, revision, json == null ? null : jsonDecode(json)));
        if (revision != entry.value) mismatch = true;
      }
      if (mismatch) {
        await tx.insert('server_requests', {
          'id': operation.id,
          'hash': hash,
          'rejected': canonicalSyncJson(remote.map((r) => r.toJson()).toList()),
        });
        return SyncRejected(remote);
      }
      for (final edit in operation.edits) {
        await tx.insert(
            'server_entities',
            {
              'kind': edit.key.kind,
              'id': edit.key.id,
              'revision': edit.baseRevision + 1,
              'value_json': edit.deleted ? null : canonicalSyncJson(edit.value),
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final effect in operation.effects) {
        await tx.rawInsert(
            'INSERT INTO server_balances(account, micros) VALUES (?, ?) '
            'ON CONFLICT(account) DO UPDATE SET micros = micros + excluded.micros',
            [effect.account, effect.deltaMicros]);
      }
      // Clock and operation commit together; no allocated but uncommitted gap.
      await tx.rawUpdate('UPDATE server_clock SET revision = revision + 1');
      final revision =
          (await tx.query('server_clock')).single['revision'] as int;
      final receipt = SyncReceipt(revision, operation, hash);
      await tx.insert('server_log', {
        'revision': revision,
        'payload': operation.encode(),
        'hash': hash,
      });
      await tx.insert('server_requests', {
        'id': operation.id,
        'hash': hash,
        'receipt': canonicalSyncJson(receipt.toJson()),
      });
      return SyncAccepted(receipt);
    });
    if (loseNextResponse) {
      loseNextResponse = false;
      throw const SyncUnavailable();
    }
    return result;
  }

  @override
  Future<List<SyncReceipt>> pull({
    required String datasetId,
    required String epoch,
    required int after,
    required int limit,
  }) async {
    if (offline) throw const SyncUnavailable();
    _binding(datasetId, epoch);
    requireSync(after >= 0 && limit > 0 && limit <= 100, 'invalid_page');
    final rows = await db.query('server_log',
        where: 'revision > ?',
        whereArgs: [after],
        orderBy: 'revision',
        limit: limit);
    return rows
        .map((r) => SyncReceipt(r['revision'] as int,
            SyncOperation.decode(r['payload'] as String), r['hash'] as String))
        .toList();
  }
}
