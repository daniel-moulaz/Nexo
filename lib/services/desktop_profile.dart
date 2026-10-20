import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_platform.dart';
import 'platform_capabilities.dart';

/// An explicit QA profile isolates synthetic data and protection preferences.
/// It never imports or copies the regular profile.
abstract final class DesktopProfile {
  static bool isTest = false;

  /// Empty for `--test-profile`; `pc2` for `--test-profile=pc2`. Each named
  /// profile is a separate synthetic device (data, preferences, PIN, session).
  static String testName = '';
  static bool _configured = false;

  /// Appended to every QA storage key so named profiles never share secrets.
  static String get qaSuffix => testName.isEmpty ? '' : '_$testName';

  static Future<void> initialize(List<String> arguments) async {
    if (!_configured) {
      if (PlatformCapabilities.windows) {
        for (final argument in arguments) {
          if (argument == '--test-profile') isTest = true;
          if (argument.startsWith('--test-profile=')) {
            final name = argument.substring('--test-profile='.length);
            if (!RegExp(r'^[a-z0-9]{1,16}$').hasMatch(name)) {
              throw StateError('Nome de perfil de teste inválido.');
            }
            isTest = true;
            testName = name;
          }
        }
      }
      if (isTest) SharedPreferences.setPrefix('nexo_windows_qa$qaSuffix.');
      _configured = true;
    }
    await DatabasePlatform.initialize(
        testDirectory: isTest
            ? p.join(Directory.systemTemp.path,
                testName.isEmpty ? 'NexoWindowsQA' : 'NexoWindowsQA-$testName')
            : null);
  }
}
