import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_profile.dart';
import 'platform_capabilities.dart';

/// Windows only: staying in the tray and starting with the system. With the
/// process alive, sync goes on and the assistant's requests are recorded with
/// no window open.
abstract final class DesktopWindow {
  static const _channel = MethodChannel('nexo/window');
  static const _keepKey = 'nexo_keep_in_tray';
  static const _autostartDefaultKey = 'nexo_autostart_default_v1';

  static Future<bool> keepInTray() async =>
      (await SharedPreferences.getInstance()).getBool(_keepKey) ?? true;

  /// Applies the saved choice. A test profile closes normally: QA windows
  /// must not pile up in the tray.
  static Future<void> start() async {
    if (!PlatformCapabilities.windows) return;
    final keep =
        DesktopProfile.isTest ? DesktopProfile.testTray : await keepInTray();
    try {
      await _channel.invokeMethod<void>('setKeepInTray', keep);
      // 1.17.0, once: the PC is the assistant's second way in, so with the
      // tray on it also starts with Windows (switch in Fila do Claude and
      // in Configurações). A choice made later is never overridden.
      final prefs = await SharedPreferences.getInstance();
      if (!DesktopProfile.isTest &&
          keep &&
          prefs.getBool(_autostartDefaultKey) != true) {
        if (!await startsWithWindows()) await setStartWithWindows(true);
        await prefs.setBool(_autostartDefaultKey, true);
      }
    } on MissingPluginException {
      // An entrypoint without the runner channel.
    }
  }

  static Future<void> setKeepInTray(bool keep) async {
    await (await SharedPreferences.getInstance()).setBool(_keepKey, keep);
    await _channel.invokeMethod<void>('setKeepInTray', keep);
  }

  static Future<bool> startsWithWindows() async =>
      await _channel.invokeMethod<bool>('startsWithWindows') ?? false;

  /// False when Windows refused the change.
  static Future<bool> setStartWithWindows(bool start) async =>
      await _channel.invokeMethod<bool>('setStartWithWindows', start) ?? false;
}
