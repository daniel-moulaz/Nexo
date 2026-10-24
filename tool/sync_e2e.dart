// End-to-end check of automatic sync against the real Supabase lab, with two
// synthetic devices in temporary databases. Never opens a personal or QA
// profile database; only reuses the session of the `--test-profile` window.
//
// flutter run -d windows -t tool/sync_e2e.dart \
//   --dart-define-from-file=tool/nexo_sync.local.json
import 'dart:async';
import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/desktop_profile.dart';
import 'package:expensy/sync/ledger_capture.dart';
import 'package:expensy/sync/ledger_sync.dart';
import 'package:expensy/sync/supabase_auth.dart';
import 'package:expensy/sync/supabase_sync_transport.dart';
import 'package:expensy/sync/sync_config.dart';
import 'package:expensy/sync/sync_controller.dart';
import 'package:expensy/sync/sync_protocol.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class _Net {
  bool offline = false, dropNextAck = false;
}

/// The real transport, with a switch to simulate no network or a response
/// lost after the server already accepted.
class _Remote implements SyncRemote {
  _Remote(this.inner, this.net);
  final SupabaseSyncTransport inner;
  final _Net net;
  void _online() {
    if (net.offline) throw const SyncUnavailable();
  }

  @override
  Future<void> createSyntheticDataset(String datasetId, String epoch) {
    _online();
    return inner.createSyntheticDataset(datasetId, epoch);
  }

  @override
  Future<void> openDataset(String datasetId, String epoch,
      {required bool real}) {
    _online();
    return inner.openDataset(datasetId, epoch, real: real);
  }

  @override
  Future<void> deleteDataset(String datasetId) =>
      inner.deleteDataset(datasetId);

  @override
  Future<void> setDatasetLabel(String datasetId, String label) =>
      inner.setDatasetLabel(datasetId, label);

  @override
  Future<List<RemoteDataset>> listDatasets({bool real = false}) =>
      inner.listDatasets(real: real);

  @override
  Future<void> revokeDevice(String datasetId, String device) =>
      inner.revokeDevice(datasetId, device);

  @override
  Future<SyncPushResult> push(SyncOperation operation) async {
    _online();
    final result = await inner.push(operation);
    if (net.dropNextAck) {
      net.dropNextAck = false;
      throw const SyncUnavailable();
    }
    return result;
  }

  @override
  Future<List<SyncReceipt>> pull(
      {required String datasetId,
      required String epoch,
      required int after,
      required int limit}) {
    _online();
    return inner.pull(
        datasetId: datasetId, epoch: epoch, after: after, limit: limit);
  }
}

final _log = StringBuffer();
void _say(String line) {
  _log.writeln(line);
  debugPrint('[e2e] $line');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Same session key as the `--test-profile` window; isolated preferences.
  DesktopProfile.isTest = true;
  SharedPreferences.setPrefix('nexo_windows_qa_e2e.');
  final out = File(p.join(Directory.systemTemp.path, 'nexo_sync_e2e.txt'));
  var failed = true;
  try {
    failed = !await _run();
  } catch (e, s) {
    _say('ERRO: $e\n$s');
  }
  await out.writeAsString(_log.toString());
  exit(failed ? 1 : 0);
}

Future<bool> _run() async {
  final config = SyncConfig.current;
  if (config == null) throw StateError('build sem tool/nexo_sync.local.json');
  final auth = SupabaseAuth(config);
  if (await auth.session() == null) {
    throw StateError('perfil de teste sem login');
  }
  final net = _Net();
  final root = await Directory.systemTemp.createTemp('NexoE2E-');
  final ids = <String, String>{};
  SyncController? current;
  String? on;

  SyncRemote remote(String device) => _Remote(
      SupabaseSyncTransport(
          projectUrl: config.projectUrl,
          publishableKey: config.publishableKey,
          deviceId: device,
          accessToken: auth.accessToken),
      net);

  SyncController controller() => SyncController(
      remote: remote,
      reload: () async {},
      debounce: const Duration(milliseconds: 300),
      interval: const Duration(hours: 1));

  Future<void> use(String device) async {
    current?.dispose();
    current = null;
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, device));
    await DBHelper.database;
    on = device;
  }

  /// Opens the app on [device]: it pulls what changed elsewhere.
  Future<SyncController> open(String device) async {
    await use(device);
    final c = current = controller();
    await c.start();
    await c.idle;
    return c;
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    await current!.idle;
  }

  Future<void> retryNow() async {
    await (await DBHelper.database)
        .update('sync_journal', {'next_retry_at': 0});
    await current!.syncNow();
  }

  Future<AppProvider> app() async {
    final a = AppProvider();
    a.settings.budgetAlertsEnabled = false;
    a.accounts = await DBHelper.getAccounts();
    a.categories = await DBHelper.getCategories();
    a.transactions = await DBHelper.getTransactions();
    return a;
  }

  Future<double> balance(String id) async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;

  Future<AppTransaction?> tx(String id) async {
    for (final t in await DBHelper.getTransactions()) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<String> snapshot() async {
    final db = await DBHelper.database;
    final parts = <String>[];
    for (final e in ledgerTables.entries) {
      for (final row in await db.query(e.key, orderBy: '${e.value} ASC')) {
        parts.add('${e.key}:${{
          ...row,
          if (e.key == 'accounts')
            'balance': ((row['balance'] as num) * 1e6).round()
        }}');
      }
    }
    return parts.join('\n');
  }

  final s = '${DateTime.now().millisecondsSinceEpoch}';
  final bank = 'e2e-bank-$s', wallet = 'e2e-wallet-$s';
  AppTransaction expense(String id, double amount) => AppTransaction(
      id: '$id-$s',
      type: 'expense',
      amount: amount,
      description: 'E2E $id',
      accountId: bank,
      categoryId: 'food_exp',
      date: DateTime(2026, 10, 20, 12),
      currency: 'BRL');
  AppCategory food(String name) =>
      AppCategory(id: 'food_exp', name: name, type: 'expense', colorValue: 0);

  var passed = 0;
  final steps = <(String, Future<void> Function())>[
    (
      'Pareamento: A cria o acervo, B entra',
      () async {
        await use('A');
        final dataset = const Uuid().v4(), epoch = const Uuid().v4();
        ids['dataset'] = dataset;
        ids['A'] = const Uuid().v4();
        await remote(ids['A']!).openDataset(dataset, epoch, real: false);
        await LedgerSync.createDataset(await DBHelper.database,
            datasetId: dataset, epoch: epoch, deviceId: ids['A']!);
        final a = await open('A');
        _check(a.summary == 'Sincronizado', 'A: ${a.summary}');
        await use('B');
        ids['B'] = const Uuid().v4();
        await remote(ids['B']!).openDataset(dataset, epoch, real: false);
        await LedgerSync.joinDataset(await DBHelper.database,
            datasetId: dataset, epoch: epoch, deviceId: ids['B']!);
        final b = await open('B');
        _check(b.summary == 'Sincronizado', 'B: ${b.summary}');
      }
    ),
    (
      'Conta criada em A chega sozinha em B',
      () async {
        await open('A');
        await (await app()).addAccount(Account(
            id: bank,
            name: 'Banco E2E',
            type: 'bank',
            balance: 1000,
            currency: 'BRL',
            colorValue: 0));
        await settle();
        _check(current!.pending == 0, 'A não enviou: ${current!.summary}');
        await open('B');
        _check(await balance(bank) == 1000, 'B saldo ${await balance(bank)}');
      }
    ),
    (
      'Despesa lançada em B chega sozinha em A (R\$ 950)',
      () async {
        await (await app()).addTransaction(expense('almoco', 50));
        await settle();
        _check(current!.pending == 0, 'B não enviou: ${current!.summary}');
        await open('A');
        _check(await tx('almoco-$s') != null, 'A não recebeu');
        _check(await balance(bank) == 950, 'A saldo ${await balance(bank)}');
      }
    ),
    (
      'Gastos simultâneos na mesma conta somam nos dois (R\$ 900)',
      () async {
        await (await app()).addTransaction(expense('mercado', 30));
        await settle();
        net.offline = true; // B ainda não viu o gasto de A
        await open('B');
        await (await app()).addTransaction(expense('padaria', 20));
        await settle();
        net.offline = false;
        await retryNow();
        _check(current!.pending == 0 && current!.conflicts.isEmpty,
            'B: ${current!.summary}');
        _check(await balance(bank) == 900, 'B saldo ${await balance(bank)}');
        await open('A');
        _check(await balance(bank) == 900, 'A saldo ${await balance(bank)}');
      }
    ),
    (
      'Mesma categoria renomeada nos dois: conflito, "Usar a minha versão"',
      () async {
        await (await app()).updateCategory(food('Comida A'));
        await settle();
        net.offline = true;
        await open('B');
        await (await app()).updateCategory(food('Comida B'));
        await settle();
        net.offline = false;
        await retryNow();
        final b = current!;
        _check(b.status == LedgerSyncStatus.conflict, 'B: ${b.summary}');
        _check(b.conflicts.length == 1 && b.conflicts.single.canReapply,
            'B conflitos ${b.conflicts.length}');
        await b.reapply(b.conflicts.single.operation.id);
        await b.idle;
        _check(b.conflicts.isEmpty && b.pending == 0, 'B: ${b.summary}');
        await open('A');
        final name = (await DBHelper.getCategories())
            .firstWhere((c) => c.id == 'food_exp')
            .name;
        _check(name == 'Comida B', 'A categoria $name');
      }
    ),
    (
      'Mesmo lançamento editado nos dois: conflito, "Manter a do outro" (R\$ 890)',
      () async {
        final original = (await tx('almoco-$s'))!;
        await (await app()).updateTransaction(expense('almoco', 60), original);
        await settle();
        net.offline = true;
        await open('B');
        final mine = (await tx('almoco-$s'))!;
        await (await app()).updateTransaction(expense('almoco', 70), mine);
        await settle();
        _check(await balance(bank) == 880, 'B local ${await balance(bank)}');
        net.offline = false;
        await retryNow();
        final b = current!;
        _check(b.conflicts.length == 1 && !b.conflicts.single.canReapply,
            'B conflitos ${b.conflicts.length}');
        _check(await balance(bank) == 890, 'B saldo ${await balance(bank)}');
        await b.discard(b.conflicts.single.operation.id);
        await b.idle;
        _check(b.conflicts.isEmpty && b.pending == 0, 'B: ${b.summary}');
        _check((await tx('almoco-$s'))!.amount == 60, 'B valor');
        await open('A');
        _check(await balance(bank) == 890, 'A saldo ${await balance(bank)}');
      }
    ),
    (
      'Apagado em A enquanto B editava: fica apagado (R\$ 920)',
      () async {
        await (await app()).deleteTransaction('mercado-$s');
        await settle();
        net.offline = true;
        await open('B');
        final mine = (await tx('mercado-$s'))!;
        await (await app()).updateTransaction(expense('mercado', 35), mine);
        await settle();
        net.offline = false;
        await retryNow();
        final b = current!;
        _check(b.conflicts.length == 1, 'B conflitos ${b.conflicts.length}');
        await b.discard(b.conflicts.single.operation.id);
        await b.idle;
        _check(await tx('mercado-$s') == null, 'B ainda tem o lançamento');
        _check(await balance(bank) == 920, 'B saldo ${await balance(bank)}');
        await open('A');
        _check(await balance(bank) == 920, 'A saldo ${await balance(bank)}');
      }
    ),
    (
      'Sem internet: fica na fila e sai quando a rede volta (R\$ 910)',
      () async {
        await open('B');
        net.offline = true;
        await (await app()).addTransaction(expense('cafe', 10));
        await settle();
        final b = current!;
        _check(b.status == LedgerSyncStatus.retryLater && b.pending == 1,
            'B: ${b.summary}');
        _check(await balance(bank) == 910, 'B local ${await balance(bank)}');
        net.offline = false;
        await retryNow();
        _check(b.pending == 0 && b.summary == 'Sincronizado', b.summary);
        await open('A');
        _check(await balance(bank) == 910, 'A saldo ${await balance(bank)}');
      }
    ),
    (
      'Resposta perdida: o reenvio não duplica (R\$ 905)',
      () async {
        net.dropNextAck = true;
        await (await app()).addTransaction(expense('agua', 5));
        await settle();
        _check(!net.dropNextAck, 'a resposta não foi descartada');
        // The same pass pulls its own operation back and confirms it.
        await retryNow();
        _check(current!.pending == 0, 'A: ${current!.summary}');
        await use('B');
        final before =
            await LedgerSync(await DBHelper.database, remote(ids['B']!)).cursor;
        await open('B');
        final after =
            await LedgerSync(await DBHelper.database, remote(ids['B']!)).cursor;
        _check(after - before == 1, 'B recebeu ${after - before} revisões');
        _check(await balance(bank) == 905, 'B saldo ${await balance(bank)}');
      }
    ),
    (
      'Transferência entre contas não cria nem some dinheiro',
      () async {
        await open('A');
        final a = await app();
        await a.addAccount(Account(
            id: wallet,
            name: 'Carteira E2E',
            type: 'cash',
            balance: 0,
            currency: 'BRL',
            colorValue: 0));
        a.accounts = await DBHelper.getAccounts();
        await a.addTransfer(fromId: bank, toId: wallet, fromAmount: 100);
        await settle();
        _check(current!.pending == 0, 'A: ${current!.summary}');
        await open('B');
        final b1 = await balance(bank), b2 = await balance(wallet);
        _check(b1 == 805 && b2 == 100, 'B banco $b1 carteira $b2');
      }
    ),
    (
      'Os dois aparelhos terminaram com dados idênticos',
      () async {
        final b = await snapshot();
        await open('A');
        final a = await snapshot();
        _check(a == b, 'A e B diferem');
        _check(current!.pending == 0 && current!.conflicts.isEmpty,
            'A: ${current!.summary}');
      }
    ),
  ];

  try {
    for (final (name, body) in steps) {
      try {
        await body();
        passed++;
        _say('OK    $name');
      } catch (e) {
        _say('FALHA $name — $e (em ${on ?? '-'})');
        return false;
      }
    }
    return true;
  } finally {
    _say('$passed/${steps.length} passos');
    current?.dispose();
    await DBHelper.close();
    // The synthetic dataset stays on the lab server; its devices lose access.
    for (final device in ['A', 'B']) {
      if (ids[device] case final id?) {
        try {
          await remote(id).revokeDevice(ids['dataset']!, id);
        } catch (_) {}
      }
    }
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  }
}

void _check(bool ok, String detail) {
  if (!ok) throw StateError(detail);
}
