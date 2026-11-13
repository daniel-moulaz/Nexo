import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import '../providers/app_provider.dart';
import '../services/desktop_profile.dart';
import '../services/diagnostics.dart';
import '../services/inbox_reconciler.dart';
import '../services/notification_inbox.dart';
import '../services/platform_capabilities.dart';
import '../services/pluggy_inbox.dart';
import 'assistant_commands.dart';
import 'claude_queue.dart';
import 'ledger_sync.dart';
import 'supabase_auth.dart';
import 'sync_config.dart';
import 'sync_controller.dart';

/// Where the pass that is running now came from (see [QueueCheck.source]).
String? _passSource;

/// Connects the assistant to sync: after every successful round this
/// device claims and applies the pending requests, then records the check.
/// [background] skips the bank inbox, which only matters with the app open.
AssistantCommands wireAssistant(AppProvider provider, SyncConfig config,
    {bool background = false}) {
  final assistant = AssistantCommands.instance = AssistantCommands(
      SupabaseAssistantRemote(config, SupabaseAuth.app!), provider);
  SyncController.instance?.afterSync = () async {
    final sync = SyncController.instance!;
    if (!sync.bound || sync.datasetId == null || sync.deviceId == null) {
      return;
    }
    // After a round, the other device's settings are already here.
    await provider.seedSharedSettings();
    final before = assistant.handled;
    var ok = true;
    try {
      await assistant.run(datasetId: sync.datasetId!, deviceId: sync.deviceId!);
    } catch (e) {
      ok = false;
      rethrow;
    } finally {
      await ClaudeQueue.record(QueueCheck(
          at: DateTime.now(),
          source:
              _passSource ?? (PlatformCapabilities.windows ? 'tray' : 'app'),
          applied: assistant.handled - before,
          ok: ok));
    }
    if (background) return;
    await InboxReconciler.background(
        pending: NotificationInbox.pending,
        transactions: provider.transactions,
        metadata: provider.transactionMetadata,
        accounts: provider.accounts,
        profileName: provider.settings.userName,
        push: () async => PluggyInbox.instance?.sync());
  };
  return assistant;
}

/// The app's own engine answers the worker (app alive but not in front).
Future<QueueCheck> runQueueInApp(String source) async {
  final sync = SyncController.instance;
  final assistant = AssistantCommands.instance;
  if (sync == null || assistant == null || !sync.bound) {
    return QueueCheck(at: DateTime.now(), source: source, note: 'sem_acervo');
  }
  final before = assistant.handled;
  _passSource = source == 'app' ? 'app' : 'background';
  try {
    await sync.syncNow();
    if (sync.pending > 0) await sync.syncNow();
  } finally {
    _passSource = null;
  }
  return QueueCheck(
      at: DateTime.now(),
      source: 'background',
      applied: assistant.handled - before,
      ok: sync.status == LedgerSyncStatus.idle ||
          sync.status == LedgerSyncStatus.progressed);
}

/// The headless pass: no screen, no timers. Loads the ledger, syncs, applies
/// what the assistant asked, sends the result and, when something was
/// recorded, says so in a notification without amounts.
Future<QueueCheck> runHeadlessQueue(String source) async {
  await DesktopProfile.initialize(const []);
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  final config = SyncConfig.current;
  if (config == null) {
    return QueueCheck(at: DateTime.now(), source: source, note: 'sem_servidor');
  }
  if (!await ClaudeQueue.enabled()) {
    return QueueCheck(at: DateTime.now(), source: source, note: 'desligado');
  }
  SupabaseAuth.app = SupabaseAuth(config);
  final provider = AppProvider();
  await provider.load();
  final sync = SyncController.instance = SyncController.forApp(
      config, SupabaseAuth.app, provider.reloadFromStorage,
      real: !DesktopProfile.isTest)!;
  final assistant = wireAssistant(provider, config, background: true);
  _passSource = source;
  try {
    await sync.runOnce();
  } finally {
    _passSource = null;
  }
  final applied = assistant.handled;
  if (applied > 0 && await ClaudeQueue.notifies()) {
    await _tell(applied);
  }
  final ok = sync.status == LedgerSyncStatus.idle ||
      sync.status == LedgerSyncStatus.progressed;
  final check = QueueCheck(
      at: DateTime.now(),
      source: source,
      applied: applied,
      ok: ok,
      note: !sync.bound ? 'sem_acervo' : (ok ? null : sync.status?.name));
  // A successful round already recorded itself; a failed one did not.
  if (!ok || !sync.bound) await ClaudeQueue.record(check);
  return check;
}

Future<void> _tell(int applied) async {
  try {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification')));
    await plugin.show(
        7318,
        'Feito pelo Claude',
        applied == 1
            ? '1 pedido gravado com o app fechado. Toque para conferir.'
            : '$applied pedidos gravados com o app fechado. Toque para conferir.',
        const NotificationDetails(
            android: AndroidNotificationDetails(
                'nexo_claude_done', 'Feito pelo Claude',
                channelDescription:
                    'Quando o Nexo grava um pedido do Claude com o app fechado. Sem valores.',
                importance: Importance.low,
                priority: Priority.low)));
  } catch (e) {
    Diagnostics.note('queue', e);
  }
}
