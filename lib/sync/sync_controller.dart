import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/db_helper.dart';
import 'ledger_capture.dart';
import 'ledger_sync.dart';
import 'supabase_auth.dart';
import 'supabase_sync_transport.dart';
import 'sync_config.dart';
import 'sync_lab_check.dart';

class RemoteDataset {
  const RemoteDataset(this.id, this.epoch, this.label, this.devices);
  final String id, epoch, label;
  final int devices;
}

/// Everything the controller needs from the server, so tests can provide a
/// local reference server instead of HTTP.
abstract interface class SyncRemote implements SyncLabTransport {
  Future<void> setDatasetLabel(String datasetId, String label);
  Future<List<RemoteDataset>> listDatasets();
}

/// Automatic synchronization while the app is open: shortly after every
/// local decision, when the app opens or returns, and every minute. Local
/// work never waits for the network; failures only delay sending.
class SyncController extends ChangeNotifier with WidgetsBindingObserver {
  SyncController({
    required this.remote,
    required this.reload,
    this.debounce = const Duration(seconds: 2),
    this.interval = const Duration(minutes: 1),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Builds a transport for this device id.
  final SyncRemote Function(String deviceId) remote;

  /// Reloads screens after changes arrived from another device.
  final Future<void> Function() reload;
  final Duration debounce, interval;
  final DateTime Function() _now;

  static SyncController? instance;

  /// The app's controller for a configured build, or null.
  static SyncController? forApp(
      SyncConfig? config, SupabaseAuth? auth, Future<void> Function() reload) {
    if (config == null || auth == null) return null;
    return SyncController(
      reload: reload,
      remote: (device) => SupabaseSyncTransport(
          projectUrl: config.projectUrl,
          publishableKey: config.publishableKey,
          deviceId: device,
          accessToken: auth.accessToken),
    );
  }

  bool bound = false, running = false;
  LedgerSyncStatus? status;
  DateTime? lastSuccess;
  int pending = 0;
  List<LedgerSyncConflict> conflicts = const [];
  String? datasetLabel;
  Timer? _debounce, _periodic;
  Future<void>? _current;
  bool _again = false, _started = false;

  static Future<Map<String, Object?>?> _binding(Database db) async {
    if (!await LedgerCapture.isInstalled(db)) return null;
    final exists = await db.rawQuery(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'sync_binding'");
    if (exists.isEmpty) return null;
    final rows = await db.query('sync_binding');
    return rows.isEmpty ? null : rows.single;
  }

  /// Starts listening when this database already belongs to a dataset.
  Future<void> start() async {
    final binding = await _binding(await DBHelper.database);
    bound = binding != null;
    datasetLabel = binding?['label'] as String?;
    if (bound && !_started) {
      _started = true;
      LedgerCapture.changes.addListener(_changed);
      WidgetsBinding.instance.addObserver(this);
      _periodic = Timer.periodic(interval, (_) => syncNow());
    }
    notifyListeners();
    if (bound) await syncNow();
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(debounce, syncNow);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!bound) return;
    if (state == AppLifecycleState.resumed) {
      _periodic?.cancel();
      _periodic = Timer.periodic(interval, (_) => syncNow());
      syncNow();
    } else if (state == AppLifecycleState.paused) {
      _periodic?.cancel();
      // Send what is pending before the system suspends the app.
      syncNow();
    }
  }

  /// Completes when no synchronization is running (for tests and screens).
  Future<void> get idle async {
    while (_current != null) {
      await _current;
    }
  }

  /// One pass now; a request during a pass schedules exactly one more.
  Future<void> syncNow() {
    if (!bound) return Future.value();
    if (_current != null) {
      _again = true;
      return _current!;
    }
    return _current = _drain().whenComplete(() => _current = null);
  }

  Future<void> _drain() async {
    do {
      _again = false;
      await _pass();
    } while (_again);
  }

  Future<void> _pass() async {
    running = true;
    notifyListeners();
    try {
      final db = await DBHelper.database;
      final binding = await _binding(db);
      if (binding == null) {
        bound = false;
        return;
      }
      final engine = LedgerSync(db, remote(binding['device_id'] as String));
      final before = await engine.cursor;
      status = await engine.synchronize();
      if (await engine.cursor != before) await reload();
      pending = await engine.pendingCount;
      conflicts = await engine.conflicts();
      if (status == LedgerSyncStatus.idle ||
          status == LedgerSyncStatus.progressed ||
          status == LedgerSyncStatus.conflict) {
        lastSuccess = _now();
      }
    } catch (_) {
      // A rejected page leaves cursor and data untouched; try again later.
      status = LedgerSyncStatus.retryLater;
    } finally {
      running = false;
      notifyListeners();
    }
  }

  String get summary => switch (status) {
        null => 'Preparando a sincronização…',
        LedgerSyncStatus.idle || LedgerSyncStatus.progressed => pending == 0
            ? 'Sincronizado'
            : '$pending alteração(ões) aguardando envio',
        LedgerSyncStatus.retryLater =>
          'Sem conexão com o servidor. $pending alteração(ões) aguardando; tudo continua salvo neste aparelho.',
        LedgerSyncStatus.conflict =>
          '${conflicts.length} conflito(s) precisam da sua decisão.',
        LedgerSyncStatus.paused =>
          'Pausado: um backup foi restaurado neste aparelho. É preciso entrar novamente no acervo.',
        LedgerSyncStatus.unattributed =>
          'Pausado por segurança: houve uma gravação que não pode ser sincronizada com garantia.',
        LedgerSyncStatus.authenticationRequired =>
          'Entre novamente na conta para continuar sincronizando.',
        LedgerSyncStatus.deviceRevoked =>
          'Este aparelho foi desconectado do acervo.',
        LedgerSyncStatus.busy => 'Sincronizando…',
      };

  /// First device: its current data becomes the dataset.
  Future<void> createDataset(String label) async {
    final dataset = const Uuid().v4(), epoch = const Uuid().v4();
    final device = const Uuid().v4();
    final server = remote(device);
    await server.createSyntheticDataset(dataset, epoch);
    await server.setDatasetLabel(dataset, label);
    await LedgerSync.createDataset(await DBHelper.database,
        datasetId: dataset, epoch: epoch, deviceId: device);
    await _rememberLabel(label);
    await start();
  }

  Future<List<RemoteDataset>> datasets() async =>
      remote(const Uuid().v4()).listDatasets();

  /// Another device: downloads the chosen dataset into an empty ledger.
  Future<void> join(RemoteDataset dataset) async {
    final device = const Uuid().v4();
    await remote(device).createSyntheticDataset(dataset.id, dataset.epoch);
    await LedgerSync.joinDataset(await DBHelper.database,
        datasetId: dataset.id, epoch: dataset.epoch, deviceId: device);
    await _rememberLabel(dataset.label);
    await start();
  }

  Future<void> _rememberLabel(String label) async {
    final db = await DBHelper.database;
    final columns = await db.rawQuery('PRAGMA table_info(sync_binding)');
    if (!columns.any((c) => c['name'] == 'label')) {
      await db.execute('ALTER TABLE sync_binding ADD COLUMN label TEXT');
    }
    await db.update('sync_binding', {'label': label});
  }

  Future<void> discard(String operationId) async {
    final db = await DBHelper.database;
    final binding = await _binding(db);
    if (binding == null) return;
    await LedgerSync(db, remote(binding['device_id'] as String))
        .discard(operationId);
    await syncNow();
  }

  Future<void> reapply(String operationId) async {
    final db = await DBHelper.database;
    final binding = await _binding(db);
    if (binding == null) return;
    await LedgerSync(db, remote(binding['device_id'] as String))
        .reapply(operationId);
    await reload();
    await syncNow();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _periodic?.cancel();
    if (_started) {
      LedgerCapture.changes.removeListener(_changed);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }
}
