import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'ledger_capture.dart';
import 'ledger_sync.dart';
import 'local_sync_server.dart';
import 'sync_protocol.dart' show SyncTransport, canonicalSyncJson;

/// Safety steps around real activation. Nothing here sends data: the
/// rehearsal runs a complete create → send → receive cycle against an
/// in-process server, and the server check downloads into a scratch copy.
abstract final class SyncActivation {
  /// Largest operation the rehearsal accepts; the server limit is 1 MiB.
  static const maxPayloadBytes = 900 * 1024;

  /// Copy of [source] with the same schema and no ledger, journal or
  /// capture: what a freshly installed device would have.
  static Future<void> emptyCopy(Database source, String path) async {
    await _vacuumInto(source, path);
    final copy = await openDatabase(path, singleInstance: false);
    try {
      for (final t in await copy.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'sync\\_%' ESCAPE '\\'")) {
        await copy.execute('DROP TRIGGER "${t['name']}"');
      }
      for (final t in await copy.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'sync\\_%' ESCAPE '\\'")) {
        await copy.execute('DROP TABLE "${t['name']}"');
      }
      for (final table in [...ledgerTables.keys, ...ledgerLocalTables]) {
        await copy.delete(table);
      }
    } finally {
      await copy.close();
    }
  }

  static Future<void> _vacuumInto(Database source, String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
    await file.parent.create(recursive: true);
    await source.execute('VACUUM INTO ?', [path]);
  }

  /// Synced data in a comparable form: rows ordered by key, balances in
  /// micro-units, numbers compared by value.
  static Future<Map<String, String>> snapshot(DatabaseExecutor db) async => {
        for (final e in ledgerTables.entries)
          e.key: canonicalSyncJson([
            for (final row in await db.query(e.key, orderBy: '${e.value} ASC'))
              {
                for (final c in row.entries)
                  c.key: e.key == 'accounts' && c.key == 'balance'
                      ? ((c.value as num) * 1e6).round()
                      : c.value is num
                          ? (c.value as num).toDouble()
                          : c.value
              }
          ])
      };

  /// Names of the tables that differ, without revealing any value.
  static String? difference(Map<String, String> a, Map<String, String> b) {
    final differ = [
      for (final table in ledgerTables.keys)
        if (a[table] != b[table]) table
    ];
    return differ.isEmpty ? null : differ.join(', ');
  }

  /// Runs until nothing is pending or arriving. Any other state is a failure.
  static Future<void> drain(LedgerSync engine) async {
    for (var i = 0; i < 10000; i++) {
      final status = await engine.synchronize(maxPages: 50);
      if (status == LedgerSyncStatus.idle) return;
      if (status != LedgerSyncStatus.progressed) {
        throw StateError(status.name);
      }
    }
    throw StateError('not_finished');
  }

  /// Keeps an untouched copy of the database before activation. Returns its
  /// path. The copy stays next to the database, as private as the database.
  static Future<String> keepCopy(Database db, String databasePath) async {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[^0-9]'), '')
        .substring(0, 14);
    final path = p.join(
        p.dirname(databasePath), 'backups', 'antes_da_sincronizacao_$stamp.db');
    await _vacuumInto(db, path);
    return path;
  }

  /// Full local rehearsal from [pristine], a closed copy of the real database:
  /// the dataset is created on a copy, sent to an in-process server and
  /// received by an empty device. Returns null when the received data is
  /// identical to the original, otherwise the tables that differ.
  static Future<String?> rehearse(Database real, String pristine,
      {required String workDirectory}) async {
    final dir = Directory(workDirectory);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final dataset = const Uuid().v4(), epoch = const Uuid().v4();
    final opened = <Database>[];
    Future<Database> open(String name) async {
      final db =
          await openDatabase(p.join(dir.path, name), singleInstance: false);
      opened.add(db);
      return db;
    }

    try {
      final expected = await snapshot(real);
      await File(pristine).copy(p.join(dir.path, 'origem.db'));
      await emptyCopy(real, p.join(dir.path, 'novo.db'));
      final server =
          SqliteSyncServer(await open('servidor.db'), dataset, epoch);
      await server.initialize();

      final origin = await open('origem.db');
      await LedgerSync.createDataset(origin,
          datasetId: dataset, epoch: epoch, deviceId: const Uuid().v4());
      final largest = Sqflite.firstIntValue(await origin
              .rawQuery('SELECT MAX(length(payload)) FROM sync_journal')) ??
          0;
      if (largest > maxPayloadBytes) return 'operação grande demais';
      await drain(LedgerSync(origin, server));
      if (await LedgerSync(origin, server).pendingCount != 0) {
        return 'envio incompleto';
      }

      final device = await open('novo.db');
      await LedgerSync.joinDataset(device,
          datasetId: dataset, epoch: epoch, deviceId: const Uuid().v4());
      await drain(LedgerSync(device, server));
      return difference(expected, await snapshot(origin)) ??
          difference(expected, await snapshot(device));
    } finally {
      for (final db in opened) {
        await db.close();
      }
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  /// Downloads the whole dataset from the server into a scratch copy, as a
  /// new device would, and compares it with [local]. The scratch device is
  /// revoked afterwards. Returns null when identical.
  static Future<String?> compareWithServer(Database local,
      {required String workDirectory,
      required SyncTransport Function(String device) remote,
      required Future<void> Function(String device) register,
      required Future<void> Function(String device) unregister}) async {
    final binding = (await local.query('sync_binding')).single;
    final dataset = binding['dataset_id'] as String;
    final epoch = binding['epoch'] as String;
    final dir = Directory(workDirectory);
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final path = p.join(dir.path, 'conferencia.db');
    final device = const Uuid().v4();
    Database? copy;
    var registered = false;
    try {
      await emptyCopy(local, path);
      copy = await openDatabase(path, singleInstance: false);
      await register(device);
      registered = true;
      await LedgerSync.joinDataset(copy,
          datasetId: dataset, epoch: epoch, deviceId: device);
      await drain(LedgerSync(copy, remote(device)));
      return difference(await snapshot(local), await snapshot(copy));
    } finally {
      await copy?.close();
      if (registered) {
        try {
          await unregister(device);
        } catch (_) {}
      }
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    }
  }
}
