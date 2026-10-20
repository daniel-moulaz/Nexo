import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/sync/ledger_capture.dart';
import 'package:expensy/sync/ledger_sync.dart';
import 'package:expensy/sync/supabase_sync_transport.dart';
import 'package:expensy/sync/sync_protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/sqlite_sync_server.dart';

const dataset = 'synthetic-dataset';
const epoch = 'epoch-1';

/// Lets a test break the network in specific ways around the real server.
class _Faulty implements SyncTransport {
  _Faulty(this.inner);
  final SyncTransport inner;
  Exception? failure;
  bool failNextPull = false;
  @override
  Future<SyncPushResult> push(SyncOperation operation) {
    if (failure != null) throw failure!;
    return inner.push(operation);
  }

  @override
  Future<List<SyncReceipt>> pull(
      {required String datasetId,
      required String epoch,
      required int after,
      required int limit}) {
    if (failure != null) throw failure!;
    if (failNextPull) {
      failNextPull = false;
      throw const SyncUnavailable();
    }
    return inner.pull(
        datasetId: datasetId, epoch: epoch, after: after, limit: limit);
  }
}

// Two synthetic devices, each a real SQLite file, and a reference server.
// No network, credentials or personal data.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late SqliteSyncServer server;
  late _Faulty network;
  late Database serverDb;

  Future<Database> use(String device) async {
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, device));
    return DBHelper.database;
  }

  Future<AppProvider> provider() async {
    final app = AppProvider();
    app.settings.budgetAlertsEnabled = false;
    app.accounts = await DBHelper.getAccounts();
    app.categories = await DBHelper.getCategories();
    app.transactions = await DBHelper.getTransactions();
    return app;
  }

  Future<LedgerSyncStatus> sync(String device) async =>
      LedgerSync(await use(device), network).synchronize();

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final db = await DBHelper.database;
    return {
      for (final entry in ledgerTables.entries)
        entry.key: [
          for (final row
              in await db.query(entry.key, orderBy: '${entry.value} ASC'))
            {
              ...row,
              if (entry.key == 'accounts')
                'balance': ((row['balance'] as num) * 1e6).round(),
            }
        ]
    };
  }

  Future<double> balance(String id) async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;

  AppTransaction tx(String id, double amount,
          {String account = 'bank', String type = 'expense'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: 'Sintético $id',
          accountId: account,
          categoryId: type == 'expense' ? 'food_exp' : 'salary',
          date: DateTime(2026, 10, 15, 12));

  Future<void> converged() async {
    await sync('phone');
    await sync('pc');
    await sync('phone');
    final phone = await snapshot();
    await sync('pc');
    final pc = await snapshot();
    for (final table in ledgerTables.keys) {
      expect(pc[table], phone[table], reason: table);
    }
  }

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-ledger-sync-');
    serverDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false));
    server = SqliteSyncServer(serverDb, dataset, epoch);
    await server.initialize();
    network = _Faulty(server);

    await use('phone');
    for (final a in [
      Account(
          id: 'bank',
          name: 'Banco sintético',
          type: 'bank',
          balance: 1000,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'cash',
          name: 'Carteira sintética',
          type: 'wallet',
          balance: 0,
          currency: 'BRL',
          colorValue: 0),
    ]) {
      await DBHelper.insertAccount(a);
    }
    await (await provider()).addTransaction(tx('shared', 100));
    await LedgerSync.createDataset(await DBHelper.database,
        datasetId: dataset, epoch: epoch, deviceId: 'phone');

    await use('pc'); // fresh install: only untouched defaults
    await LedgerSync.joinDataset(await DBHelper.database,
        datasetId: dataset, epoch: epoch, deviceId: 'pc');
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    await serverDb.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  test('second device downloads exactly the first device ledger', () async {
    expect(await sync('phone'), LedgerSyncStatus.progressed);
    expect(await sync('pc'), LedgerSyncStatus.progressed);
    final pc = await snapshot();
    await use('phone');
    expect(pc, await snapshot());
    expect(await server.balanceMicros('bank'), 900 * 1000000);
    expect(await sync('phone'), LedgerSyncStatus.idle);
    expect(await sync('pc'), LedgerSyncStatus.idle);
  });

  test('both devices spend offline from one account and converge', () async {
    await converged();
    await use('phone');
    await (await provider()).addTransaction(tx('coffee', 7.5));
    await use('pc');
    final pcApp = await provider();
    await pcApp.addTransaction(tx('market', 0.1));
    await pcApp.addTransaction(tx('bus', 0.2));
    await pcApp.addTransfer(fromId: 'bank', toId: 'cash', fromAmount: 50);
    await pcApp.addTransaction(tx('salary', 1500, type: 'income'));

    // PC first: then the phone pulls the PC's work beneath its own.
    expect(await sync('pc'), LedgerSyncStatus.progressed);
    expect(await sync('phone'), LedgerSyncStatus.progressed);
    await converged();
    expect(await balance('bank'),
        closeTo(1000 - 100 - 7.5 - .3 - 50 + 1500, 1e-9));
    expect(await balance('cash'), 50);
    expect(await server.balanceMicros('bank'), 2342200000);
    expect(await LedgerSync(await DBHelper.database, network).pendingCount, 0);
  });

  test('a lost acknowledgement is retried with the same id, moving money once',
      () async {
    await converged();
    await use('phone');
    await (await provider()).addTransaction(tx('rent', 300));
    // The server commits, the answer is lost and the network then drops.
    server.loseNextResponse = true;
    network.failNextPull = true;
    expect(await sync('phone'), LedgerSyncStatus.retryLater);
    final revision = await server.revision;
    // Retry window elapsed: same operation id, server returns old receipt.
    await (await DBHelper.database)
        .update('sync_journal', {'next_retry_at': 0});
    expect(await sync('phone'), LedgerSyncStatus.progressed);
    expect(await server.revision, revision);
    await converged();
    expect(await balance('bank'), 600);
  });

  test('editing one transaction on both devices keeps one version and money',
      () async {
    await converged();
    AppTransaction amount(AppTransaction t, double value) => AppTransaction(
        id: t.id,
        type: t.type,
        amount: value,
        description: t.description,
        accountId: t.accountId,
        categoryId: t.categoryId,
        date: t.date);
    await use('phone');
    final phoneApp = await provider();
    final shared = phoneApp.transactions.single;
    await phoneApp.updateTransaction(amount(shared, 120), shared);
    await sync('phone');

    await use('pc');
    final pcApp = await provider();
    await pcApp.updateTransaction(
        amount(pcApp.transactions.single, 90), pcApp.transactions.single);
    expect(await balance('bank'), 910, reason: 'pc offline edit');
    expect(await sync('pc'), LedgerSyncStatus.conflict);
    expect(await balance('bank'), 880, reason: 'pc now shows the phone edit');
    final engine = LedgerSync(await DBHelper.database, network);
    final conflict = (await engine.conflicts()).single;
    expect(conflict.operation.kind, 'transaction.update');
    expect(conflict.canReapply, false, reason: 'it moves money');
    expect(conflict.operation.edits.first.value?['amount'], 90);
    await expectLater(engine.reapply(conflict.operation.id), throwsStateError);
    await engine.discard(conflict.operation.id);
    expect(await sync('pc'), LedgerSyncStatus.idle);
    await converged();
    expect(await balance('bank'), 880);
  });

  test('an effect-free conflict can keep the local alternative', () async {
    await converged();
    AppCategory food(String name) =>
        AppCategory(id: 'food_exp', name: name, type: 'expense', colorValue: 0);
    await use('phone');
    await (await provider()).updateCategory(food('Comida'));
    await sync('phone');
    await use('pc');
    await (await provider()).updateCategory(food('Mercado e restaurantes'));
    expect(await sync('pc'), LedgerSyncStatus.conflict);
    final engine = LedgerSync(await DBHelper.database, network);
    final conflict = (await engine.conflicts()).single;
    expect(conflict.canReapply, true);
    await engine.reapply(conflict.operation.id);
    await converged();
    expect(
        (await DBHelper.getCategories())
            .firstWhere((c) => c.id == 'food_exp')
            .name,
        'Mercado e restaurantes');
  });

  test('spending on an account deleted elsewhere becomes a conflict', () async {
    await converged();
    await use('phone');
    await (await provider()).deleteAccount('cash');
    await sync('phone');
    await use('pc');
    await (await provider()).addTransaction(tx('gift', 30, account: 'cash'));
    expect(await sync('pc'), LedgerSyncStatus.conflict);
    expect((await DBHelper.getTransactions()).where((t) => t.id == 'gift'),
        isEmpty);
    expect((await DBHelper.getAccounts()).map((a) => a.id), ['bank']);
    expect(await server.balanceMicros('cash'), 0);
    await converged();
  });

  test('a failure while receiving keeps cursor and ledger unchanged', () async {
    await sync('phone');
    final pc = await use('pc');
    await pc.execute('''CREATE TRIGGER fail_receive BEFORE INSERT ON
        transactions BEGIN SELECT RAISE(ABORT, 'synthetic disk failure'); END''');
    await expectLater(LedgerSync(pc, network).synchronize(), throwsA(anything));
    expect(await LedgerSync(pc, network).cursor, 0);
    expect(await DBHelper.getAccounts(), isEmpty);
    await pc.execute('DROP TRIGGER fail_receive');
    expect(await sync('pc'), LedgerSyncStatus.progressed);
    await converged();
  });

  test('unattributed writes, restores and revoked devices stop the engine',
      () async {
    await converged();
    final phone = await use('phone');
    final pushes = server.pushes;
    await phone.insert('wishlist', {
      'id': 'raw',
      'name': 'Escrita direta',
      'target_price': 1.0,
      'priority': 'low',
      'created_at': DateTime(2026).toIso8601String(),
    });
    expect(await sync('phone'), LedgerSyncStatus.unattributed);
    expect(server.pushes, pushes);

    await use('pc');
    network.failure = const SyncDeviceRevoked();
    expect(await sync('pc'), LedgerSyncStatus.deviceRevoked);
    network.failure = const SyncAuthenticationRequired();
    expect(await sync('pc'), LedgerSyncStatus.authenticationRequired);
    network.failure = const SyncUnavailable();
    expect(await sync('pc'), LedgerSyncStatus.retryLater);
    network.failure = null;

    await DBHelper.importAll(await DBHelper.exportAll());
    expect(await sync('pc'), LedgerSyncStatus.paused);
  });

  test('a device with its own data cannot silently join', () async {
    final other = await use('other');
    await DBHelper.insertAccount(Account(
        id: 'mine',
        name: 'Minha conta',
        type: 'bank',
        balance: 10,
        currency: 'BRL',
        colorValue: 0));
    await expectLater(
        LedgerSync.joinDataset(other,
            datasetId: dataset, epoch: epoch, deviceId: 'other'),
        throwsStateError);
    expect((await DBHelper.getAccounts()).single.balance, 10);
    expect(await LedgerCapture.isInstalled(other), false);
  });
}
