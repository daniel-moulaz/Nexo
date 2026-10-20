import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/sync/ledger_capture.dart';
import 'package:expensy/sync/ledger_sync.dart';
import 'package:expensy/sync/sync_controller.dart';
import 'package:expensy/sync/sync_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sqlite_sync_server.dart';

/// Local stand-in for the Supabase lab RPCs.
class _Lab {
  final servers = <String, SqliteSyncServer>{};
  final labels = <String, String>{};
  final epochs = <String, String>{};
  bool offline = false;
}

class _Remote implements SyncRemote {
  _Remote(this.lab, this.id);
  final _Lab lab;
  final String id;
  void _online() {
    if (lab.offline) throw const SyncUnavailable();
  }

  @override
  Future<void> createSyntheticDataset(String datasetId, String epoch) async {
    _online();
    if (lab.servers.containsKey(datasetId)) return;
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    final server = SqliteSyncServer(db, datasetId, epoch);
    await server.initialize();
    lab.servers[datasetId] = server;
    lab.epochs[datasetId] = epoch;
  }

  @override
  Future<void> setDatasetLabel(String datasetId, String label) async =>
      lab.labels[datasetId] = label;

  @override
  Future<List<RemoteDataset>> listDatasets() async {
    _online();
    return [
      for (final e in lab.labels.entries)
        RemoteDataset(e.key, lab.epochs[e.key]!, e.value, 1)
    ];
  }

  @override
  Future<void> revokeDevice(String datasetId, String device) async {}

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    _online();
    return lab.servers[operation.datasetId]!.push(operation);
  }

  @override
  Future<List<SyncReceipt>> pull(
      {required String datasetId,
      required String epoch,
      required int after,
      required int limit}) async {
    _online();
    return lab.servers[datasetId]!
        .pull(datasetId: datasetId, epoch: epoch, after: after, limit: limit);
  }
}

// Two synthetic devices with real SQLite files; no network or real data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Lab lab;
  var reloads = 0;

  Future<void> use(String device) async {
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, device));
    await DBHelper.database;
  }

  SyncController controller() => SyncController(
      remote: (id) => _Remote(lab, id),
      reload: () async => reloads++,
      debounce: const Duration(milliseconds: 20),
      interval: const Duration(hours: 1));

  Future<AppProvider> provider() async {
    final app = AppProvider();
    app.settings.budgetAlertsEnabled = false;
    app.accounts = await DBHelper.getAccounts();
    app.categories = await DBHelper.getCategories();
    app.transactions = await DBHelper.getTransactions();
    return app;
  }

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final db = await DBHelper.database;
    return {
      for (final e in ledgerTables.entries)
        e.key: [
          for (final row in await db.query(e.key, orderBy: '${e.value} ASC'))
            {
              ...row,
              if (e.key == 'accounts')
                'balance': ((row['balance'] as num) * 1e6).round(),
            }
        ]
    };
  }

  AppTransaction expense(String id, double amount) => AppTransaction(
      id: id,
      type: 'expense',
      amount: amount,
      description: 'Sintético $id',
      accountId: 'bank',
      categoryId: 'food_exp',
      date: DateTime(2026, 10, 20, 12));

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-sync-controller-');
    lab = _Lab();
    reloads = 0;
    await use('phone');
    await DBHelper.insertAccount(Account(
        id: 'bank',
        name: 'Banco sintético',
        type: 'bank',
        balance: 1000,
        currency: 'BRL',
        colorValue: 0));
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  /// Phone creates the dataset; PC joins it. Each controller is disposed
  /// before switching, as only one device runs per process in the app.
  Future<void> pair() async {
    final phone = controller();
    await phone.createDataset('Teste celular e PC');
    await phone.idle;
    expect(phone.bound, true);
    expect(phone.pending, 0);
    phone.dispose();
    await use('pc');
    final pc = controller();
    final found = await pc.datasets();
    expect(found.single.label, 'Teste celular e PC');
    await pc.join(found.single);
    await pc.idle;
    expect(pc.summary, 'Sincronizado');
    pc.dispose();
  }

  test('an expense saved on one device is sent by itself and received',
      () async {
    await pair();
    final pcState = await snapshot();
    await use('phone');
    expect(await snapshot(), pcState, reason: 'PC downloaded the dataset');

    final phone = controller();
    await phone.start();
    await phone.idle;
    final before = await lab.servers.values.single.revision;
    await (await provider()).addTransaction(expense('coffee', 7.5));
    // No button: the commit itself schedules the upload.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await phone.idle;
    expect(await lab.servers.values.single.revision, before + 1);
    expect(phone.pending, 0);
    phone.dispose();

    await use('pc');
    reloads = 0;
    final pc = controller();
    await pc.start(); // opening the app pulls what changed
    await pc.idle;
    expect((await DBHelper.getTransactions()).map((t) => t.id),
        contains('coffee'));
    expect((await DBHelper.getAccounts()).single.balance, 992.5);
    expect(reloads, greaterThan(0), reason: 'screens refresh by themselves');
    pc.dispose();
  });

  test('offline work waits in the queue and leaves when the network returns',
      () async {
    await pair();
    final pc = controller();
    await pc.start();
    await pc.idle;
    lab.offline = true;
    await (await provider()).addTransaction(expense('offline', 20));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pc.idle;
    expect(pc.status, LedgerSyncStatus.retryLater);
    expect(pc.pending, 1);
    expect(pc.summary, contains('aguardando'));
    expect((await DBHelper.getAccounts()).single.balance, 980,
        reason: 'local work never waits for the network');
    lab.offline = false;
    await (await DBHelper.database)
        .update('sync_journal', {'next_retry_at': 0});
    await pc.syncNow();
    expect(pc.pending, 0);
    expect(pc.summary, 'Sincronizado');
    pc.dispose();
  });

  test('a conflict is shown with the decision to keep or reapply', () async {
    await pair();
    AppCategory food(String name) =>
        AppCategory(id: 'food_exp', name: name, type: 'expense', colorValue: 0);
    await use('phone');
    final phone = controller();
    await phone.start();
    await (await provider()).updateCategory(food('Comida'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await phone.idle;
    phone.dispose();

    await use('pc');
    final pc = controller();
    // Offline edit of the same category, then the device comes online.
    lab.offline = true;
    await pc.start();
    await (await provider()).updateCategory(food('Mercado'));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await pc.idle;
    lab.offline = false;
    await (await DBHelper.database)
        .update('sync_journal', {'next_retry_at': 0});
    await pc.syncNow();
    expect(pc.status, LedgerSyncStatus.conflict);
    expect(pc.conflicts.single.canReapply, true);
    expect(pc.summary, contains('conflito'));
    await pc.reapply(pc.conflicts.single.operation.id);
    await pc.idle;
    expect(pc.conflicts, isEmpty);
    expect(
        (await DBHelper.getCategories())
            .firstWhere((c) => c.id == 'food_exp')
            .name,
        'Mercado');
    pc.dispose();
  });

  test('a device that never joined does not sync or touch the server',
      () async {
    final alone = controller();
    await alone.start();
    expect(alone.bound, false);
    await alone.syncNow();
    expect(lab.servers, isEmpty);
    expect(await LedgerCapture.isInstalled(await DBHelper.database), false);
    alone.dispose();
  });
}
