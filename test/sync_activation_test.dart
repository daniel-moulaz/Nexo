import 'dart:io';

import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/sync/ledger_capture.dart';
import 'package:nexo/sync/ledger_sync.dart';
import 'package:nexo/sync/local_sync_server.dart';
import 'package:nexo/sync/sync_activation.dart';
import 'package:nexo/sync/sync_controller.dart';
import 'package:nexo/sync/sync_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Local stand-in for the server: one real dataset per person, kinds never
/// mixed, like `202610210001_sync_real_datasets.sql`.
class _Server {
  final datasets = <String, SqliteSyncServer>{};
  final epochs = <String, String>{};
  final labels = <String, String>{};
  final real = <String>{};
  final revoked = <String>{};
}

class _Remote implements SyncRemote {
  _Remote(this.server);
  final _Server server;

  @override
  Future<void> createSyntheticDataset(String datasetId, String epoch) =>
      openDataset(datasetId, epoch, real: false);

  @override
  Future<void> openDataset(String datasetId, String epoch,
      {required bool real}) async {
    if (server.datasets.containsKey(datasetId)) {
      if (server.real.contains(datasetId) != real) {
        throw const SyncProtocolException('dataset_kind_mismatch');
      }
      return;
    }
    if (real && server.real.isNotEmpty) {
      throw const SyncProtocolException('real_dataset_exists');
    }
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    server.datasets[datasetId] = SqliteSyncServer(db, datasetId, epoch);
    await server.datasets[datasetId]!.initialize();
    server.epochs[datasetId] = epoch;
    if (real) server.real.add(datasetId);
  }

  @override
  Future<void> deleteDataset(String datasetId) async {
    server.datasets.remove(datasetId);
    server.labels.remove(datasetId);
    server.real.remove(datasetId);
  }

  @override
  Future<void> setDatasetLabel(String datasetId, String label) async =>
      server.labels[datasetId] = label;

  @override
  Future<List<RemoteDataset>> listDatasets({bool real = false}) async => [
        for (final e in server.labels.entries)
          if (server.real.contains(e.key) == real)
            RemoteDataset(e.key, server.epochs[e.key]!, e.value, 1)
      ];

  @override
  Future<void> revokeDevice(String datasetId, String device) async =>
      server.revoked.add(device);

  @override
  Future<SyncPushResult> push(SyncOperation operation) =>
      server.datasets[operation.datasetId]!.push(operation);

  @override
  Future<List<SyncReceipt>> pull(
          {required String datasetId,
          required String epoch,
          required int after,
          required int limit}) =>
      server.datasets[datasetId]!
          .pull(datasetId: datasetId, epoch: epoch, after: after, limit: limit);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Server server;

  Future<void> use(String device) async {
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, device));
    await DBHelper.database;
  }

  SyncController controller({bool real = true}) => SyncController(
      remote: (_) => _Remote(server),
      reload: () async {},
      debounce: const Duration(milliseconds: 20),
      interval: const Duration(hours: 1),
      real: real);

  Future<AppProvider> app() async {
    final a = AppProvider();
    a.settings.budgetAlertsEnabled = false;
    a.accounts = await DBHelper.getAccounts();
    a.categories = await DBHelper.getCategories();
    a.transactions = await DBHelper.getTransactions();
    return a;
  }

  /// Fictitious but varied ledger: two accounts, a transfer, a custom
  /// category and long notes, so checkpoints split by size.
  Future<void> seed({int expenses = 40, int noteLength = 50}) async {
    final a = await app();
    await a.addAccount(Account(
        id: 'bank',
        name: 'Banco fictício',
        type: 'bank',
        balance: 5000,
        currency: 'BRL',
        colorValue: 0));
    await a.addAccount(Account(
        id: 'wallet',
        name: 'Carteira fictícia',
        type: 'cash',
        balance: 0,
        currency: 'BRL',
        colorValue: 0));
    await a.addCategory(
        AppCategory(id: 'pets', name: 'Pets', type: 'expense', colorValue: 1));
    a.accounts = await DBHelper.getAccounts();
    for (var i = 0; i < expenses; i++) {
      await a.addTransaction(AppTransaction(
          id: 'e$i',
          type: 'expense',
          amount: 10.25 + i,
          description: 'Gasto fictício $i',
          accountId: 'bank',
          categoryId: i.isEven ? 'pets' : 'food_exp',
          date: DateTime(2026, 9, 1 + i % 28, 12),
          note: 'n' * noteLength,
          currency: 'BRL'));
    }
    await a.addTransfer(fromId: 'bank', toId: 'wallet', fromAmount: 300);
  }

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-activation-');
    server = _Server();
    await use('phone');
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('the rehearsal approves real-shaped data without touching it', () async {
    await seed();
    final db = await DBHelper.database;
    final before = await SyncActivation.snapshot(db);
    final kept = await SyncActivation.keepCopy(db, await DatabasePlatform.path);
    final work = p.join(root.path, 'work');
    expect(await SyncActivation.rehearse(db, kept, workDirectory: work), null);
    expect(await LedgerCapture.isInstalled(db), false,
        reason: 'the rehearsal runs on copies only');
    expect(await SyncActivation.snapshot(db), before);
    expect(File(kept).existsSync(), true, reason: 'the copy is kept');
    expect(Directory(work).existsSync(), false);
  });

  test('a difference names the tables, never the values', () async {
    await seed(expenses: 3);
    final db = await DBHelper.database;
    final empty = p.join(root.path, 'empty.db');
    await SyncActivation.emptyCopy(db, empty);
    final copy = await openDatabase(empty, singleInstance: false);
    final diff = SyncActivation.difference(
        await SyncActivation.snapshot(db), await SyncActivation.snapshot(copy));
    await copy.close();
    expect(diff, contains('transactions'));
    expect(diff, contains('accounts'));
    expect(diff, isNot(contains('Banco')));
  });

  test('checkpoints are split by size below the server limit', () async {
    await seed(expenses: 120, noteLength: 4000);
    final db = await DBHelper.database;
    await LedgerSync.createDataset(db,
        datasetId: '00000000-0000-4000-8000-000000000001',
        epoch: '00000000-0000-4000-8000-000000000002',
        deviceId: '00000000-0000-4000-8000-000000000003');
    final sizes = [
      for (final r in await db.rawQuery(
          "SELECT length(payload) AS n FROM sync_journal WHERE kind = 'bootstrap.checkpoint'"))
        r['n'] as int
    ];
    expect(sizes.length, greaterThan(1));
    expect(sizes.every((n) => n < SyncActivation.maxPayloadBytes), true);
  });

  test('phone activates, PC joins, both verified identical', () async {
    await seed();
    final phone = controller();
    final steps = <String>[];
    await phone.activate('Nexo', onStep: steps.add);
    expect(phone.bound, true);
    expect(phone.pending, 0);
    expect(phone.lastVerified, isNotNull);
    expect(steps.first, contains('cópia'));
    expect(steps.last, contains('Conferindo'));
    final dir = p.dirname(await DatabasePlatform.path);
    expect(
        Directory(p.join(dir, 'backups'))
            .listSync()
            .any((f) => f.path.contains('antes_da_sincronizacao_')),
        true);
    expect(Directory(p.join(dir, 'sync_trabalho')).existsSync(), false);
    final phoneData = await SyncActivation.snapshot(await DBHelper.database);
    phone.dispose();

    await use('pc');
    final pc = controller();
    final found = await pc.datasets();
    expect(found.single.label, 'Nexo');
    await pc.join(found.single);
    expect(pc.lastVerified, isNotNull);
    expect(await SyncActivation.snapshot(await DBHelper.database), phoneData);
    expect((await DBHelper.getAccounts()).map((a) => a.balance).toSet(),
        {5000 - 300 - (10.25 * 40 + 780), 300});
    pc.dispose();
  });

  test('verification catches a local change the server does not have',
      () async {
    await seed(expenses: 3);
    final phone = controller();
    await phone.activate('Nexo');
    // A raw write that escaped the domain rules.
    await (await DBHelper.database)
        .update('transactions', {'amount': 999}, where: "id = 'e0'");
    expect(await phone.verify(), 'transactions');
    expect(phone.lastVerified, null);
    phone.dispose();
  });

  test('real and test datasets never mix', () async {
    await seed(expenses: 1);
    final lab = controller(real: false);
    await lab.createDataset('Teste');
    lab.dispose();
    final real = controller();
    expect(await real.datasets(), isEmpty,
        reason: 'the test dataset is invisible to the real profile');
    await use('pc');
    final pc = controller();
    final synthetic = server.labels.keys.single;
    await expectLater(
        pc.join(RemoteDataset(synthetic, server.epochs[synthetic]!, 'x', 1)),
        throwsA(isA<SyncProtocolException>()));
    expect(await LedgerCapture.isInstalled(await DBHelper.database), false);
    pc.dispose();
    real.dispose();
  });

  test('a second origin is refused and leaves nothing behind', () async {
    await seed(expenses: 1);
    final phone = controller();
    await phone.activate('Nexo');
    phone.dispose();
    await use('tablet');
    await seed(expenses: 2);
    final tablet = controller();
    await expectLater(
        tablet.activate('Outro'), throwsA(isA<SyncProtocolException>()));
    expect(tablet.bound, false);
    expect(server.real.length, 1);
    tablet.dispose();
  });

  test('a device with its own data cannot join and is told why', () async {
    await seed(expenses: 1);
    final phone = controller();
    await phone.activate('Nexo');
    phone.dispose();
    await use('pc');
    await seed(expenses: 1);
    final pc = controller();
    await expectLater(
        pc.join((await pc.datasets()).single),
        throwsA(isA<SyncActivationFailed>().having(
            (e) => e.message, 'message', contains('Escolha qual acervo'))));
    pc.dispose();
  });
}
