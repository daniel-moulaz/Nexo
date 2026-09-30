import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show SqflitePlugin;

/// Configure once before opening SQLite. Android keeps its original factory.
abstract final class DatabasePlatform {
  static String? _directory;
  static bool _factoryConfigured = false;
  static Future<void> initialize({String? testDirectory}) async {
    if (!Platform.isWindows) {
      if (Platform.isAndroid) SqflitePlugin.registerWith();
      return;
    }
    if (!_factoryConfigured) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _factoryConfigured = true;
    }
    final local = Platform.environment['LOCALAPPDATA'];
    if (testDirectory == null && (local == null || local.isEmpty)) {
      throw StateError('O diretório de dados do Windows não está disponível.');
    }
    _directory = testDirectory ?? p.join(local!, 'Nexo');
    await Directory(_directory!).create(recursive: true);
  }

  static Future<String> get path async =>
      p.join(_directory ?? await getDatabasesPath(), 'expensy.db');
}
