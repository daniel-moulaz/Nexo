import 'package:nexo/sync/supabase_sync_transport.dart';
import 'package:nexo/sync/sync_lab_check.dart';
import 'package:nexo/sync/sync_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sqlite_sync_server.dart';

/// Local stand-in for the lab RPCs: one reference server per dataset and
/// device revocation, mirroring the PostgreSQL functions.
class _Lab {
  final servers = <String, SqliteSyncServer>{};
  final revoked = <String>{};
}

class _Device implements SyncLabTransport {
  _Device(this.lab, this.id);
  final _Lab lab;
  final String id;
  static const pageSize = 3; // like the real transport

  void _allowed() {
    if (lab.revoked.contains(id)) throw const SyncDeviceRevoked();
  }

  @override
  Future<void> createSyntheticDataset(String datasetId, String epoch) async {
    _allowed();
    if (lab.servers.containsKey(datasetId)) return;
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    final server = SqliteSyncServer(db, datasetId, epoch);
    await server.initialize();
    lab.servers[datasetId] = server;
  }

  @override
  Future<void> revokeDevice(String datasetId, String device) async =>
      lab.revoked.add(device);

  @override
  Future<SyncPushResult> push(SyncOperation operation) {
    _allowed();
    return lab.servers[operation.datasetId]!.push(operation);
  }

  @override
  Future<List<SyncReceipt>> pull(
      {required String datasetId,
      required String epoch,
      required int after,
      required int limit}) {
    _allowed();
    return lab.servers[datasetId]!.pull(
        datasetId: datasetId,
        epoch: epoch,
        after: after,
        limit: limit < pageSize ? limit : pageSize);
  }
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('every lab step passes against a correct server', () async {
    final lab = _Lab();
    final steps = await SyncLabCheck((id) => _Device(lab, id)).run();
    for (final step in steps) {
      expect(step.passed, true, reason: '${step.label}: ${step.detail}');
    }
    expect(steps, hasLength(7));
    final server = lab.servers.values.single;
    expect(await server.balanceMicros('lab-bank'), 992200000,
        reason: '1000 - 7.50 - 0.30; the stale spend never applied');
  });

  test('an expired session is reported, not thrown', () async {
    final steps = await SyncLabCheck((_) => _Failing()).run();
    expect(steps.single.passed, false);
    expect(steps.single.detail, contains('Sessão expirada'));
  });
}

class _Failing implements SyncLabTransport {
  @override
  Future<void> createSyntheticDataset(String datasetId, String epoch) =>
      throw const SyncAuthenticationRequired();
  @override
  Future<void> revokeDevice(String datasetId, String device) async {}
  @override
  Future<SyncPushResult> push(SyncOperation operation) =>
      throw UnimplementedError();
  @override
  Future<List<SyncReceipt>> pull(
          {required String datasetId,
          required String epoch,
          required int after,
          required int limit}) =>
      throw UnimplementedError();
}
