import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_platform.dart';
import 'platform_capabilities.dart';

/// An explicit QA profile isolates synthetic data and protection preferences.
/// It never imports or copies the regular profile.
abstract final class DesktopProfile {
  static bool isTest = false;
  static bool _configured = false;
  static Future<void> initialize(List<String> arguments) async {
    if (!_configured) {
      isTest =
          PlatformCapabilities.windows && arguments.contains('--test-profile');
      if (isTest) SharedPreferences.setPrefix('nexo_windows_qa.');
      _configured = true;
    }
    await DatabasePlatform.initialize(
        testDirectory:
            isTest ? p.join(Directory.systemTemp.path, 'NexoWindowsQA') : null);
  }
}
