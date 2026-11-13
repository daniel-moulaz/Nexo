import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/diagnostics.dart';

/// One look at the assistant's queue by this device.
class QueueCheck {
  const QueueCheck(
      {required this.at,
      required this.source,
      this.applied = 0,
      this.ok = true,
      this.note});

  final DateTime at;

  /// `app` (open), `background` (app alive behind other apps), `periodic`
  /// (every 15 minutes), `push` (the server's silent message) or `tray`.
  final String source;
  final int applied;
  final bool ok;
  final String? note;

  Map<String, Object?> toJson() => {
        'at': at.millisecondsSinceEpoch,
        'source': source,
        'applied': applied,
        'ok': ok,
        if (note != null) 'note': note,
      };

  static QueueCheck? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at'];
    if (at is! int) return null;
    return QueueCheck(
        at: DateTime.fromMillisecondsSinceEpoch(at),
        source: raw['source'] as String? ?? 'app',
        applied: (raw['applied'] as num?)?.toInt() ?? 0,
        ok: raw['ok'] != false,
        note: raw['note'] as String?);
  }

  String get sourceLabel => switch (source) {
        'push' => 'aviso do servidor',
        'periodic' => 'checagem a cada 15 min',
        'background' => 'app em segundo plano',
        'tray' => 'bandeja do PC',
        _ => 'app aberto',
      };
}

/// The phone side of "requests recorded with the app closed". The native
/// part is `NexoBackground.kt`; this keeps the switch, the last check and
/// the bridge to the app's engine.
abstract final class ClaudeQueue {
  static const channel = MethodChannel('nexo/background');
  static const _enabledKey = 'nexo_claude_background_v1';
  static const _notifyKey = 'nexo_claude_background_notify_v1';
  static const _lastKey = 'nexo_claude_queue_last_v1';
  static const _lastAppliedKey = 'nexo_claude_queue_last_applied_v1';
  static const _pushKey = 'nexo_claude_push_registered_v1';

  static bool get supported => Platform.isAndroid;

  /// Before the app opens its database: a headless pass may be writing.
  static Future<void> waitForHeadless() async {
    if (!supported) return;
    try {
      await channel
          .invokeMethod<void>('waitForHeadless')
          .timeout(const Duration(seconds: 90));
    } catch (_) {
      // No native side (tests) or it took too long: go on.
    }
  }

  static Future<SharedPreferences> _prefs() async {
    final prefs = await SharedPreferences.getInstance();
    // Another isolate (the headless pass) may have written meanwhile.
    await prefs.reload();
    return prefs;
  }

  static Future<bool> enabled() async =>
      (await _prefs()).getBool(_enabledKey) ?? true;

  static Future<bool> notifies() async =>
      (await _prefs()).getBool(_notifyKey) ?? true;

  static Future<void> setNotifies(bool on) async =>
      (await _prefs()).setBool(_notifyKey, on);

  static Future<void> setEnabled(bool on) async {
    await (await _prefs()).setBool(_enabledKey, on);
    await schedule();
  }

  /// Keeps the 15-minute check in step with the switch.
  static Future<void> schedule() async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('schedule', await enabled());
    } catch (e) {
      Diagnostics.note('queue', e);
    }
  }

  /// The app's engine answers the worker: one sync pass, as in front.
  static void listen(Future<QueueCheck> Function(String source) pass) {
    if (!supported) return;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'runQueue') throw MissingPluginException();
      final check = await pass(call.arguments as String? ?? 'periodic');
      return check.toJson();
    });
  }

  static Future<void> runNow() async {
    if (!supported) return;
    try {
      await channel.invokeMethod<void>('runNow');
    } catch (_) {}
  }

  static Future<void> record(QueueCheck check) async {
    final prefs = await _prefs();
    await prefs.setString(_lastKey, jsonEncode(check.toJson()));
    if (check.applied > 0) {
      await prefs.setString(_lastAppliedKey, jsonEncode(check.toJson()));
    }
  }

  static Future<QueueCheck?> last() async {
    final raw = (await _prefs()).getString(_lastKey);
    return raw == null ? null : QueueCheck.fromJson(jsonDecode(raw));
  }

  static Future<QueueCheck?> lastApplied() async {
    final raw = (await _prefs()).getString(_lastAppliedKey);
    return raw == null ? null : QueueCheck.fromJson(jsonDecode(raw));
  }

  static Future<bool> pushConfigured() async {
    if (!supported) return false;
    try {
      return await channel.invokeMethod<bool>('pushConfigured') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Registers this phone's push token once per token and device. [register]
  /// sends it to the server; a null token (push off) removes it there.
  static Future<bool> registerPush(String datasetId, String deviceId,
      Future<void> Function(String? token) register) async {
    if (!supported || !await pushConfigured()) return false;
    String? token;
    try {
      token = await channel
          .invokeMethod<String>('pushToken')
          .timeout(const Duration(seconds: 20));
    } catch (_) {}
    if (token == null) return false;
    final prefs = await _prefs();
    final want = await enabled() ? token : null;
    final key = '$datasetId|$deviceId|${want ?? '-'}';
    if (prefs.getString(_pushKey) == key) return want != null;
    await register(want);
    await prefs.setString(_pushKey, key);
    return want != null;
  }

  /// Android's battery setting for the app and whether it is a Xiaomi.
  static Future<({bool unrestricted, bool xiaomi})?> battery() async {
    if (!supported) return null;
    try {
      final r = await channel.invokeMapMethod<String, Object?>('battery');
      return (
        unrestricted: r?['unrestricted'] == true,
        xiaomi: r?['xiaomi'] == true
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> openBattery() async {
    try {
      await channel.invokeMethod<void>('openBattery');
    } catch (_) {}
  }

  static Future<bool> openAutostart() async {
    try {
      return await channel.invokeMethod<bool>('openAutostart') ?? false;
    } catch (_) {
      return false;
    }
  }
}
