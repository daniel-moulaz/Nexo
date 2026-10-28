import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' show SqflitePlugin;

/// Configure once before opening SQLite. Android keeps its original factory.
abstract final class DatabasePlatform {
  /// The database file. Until 1.12.9 it was called `expensy.db`; the first
  /// open after that update renames it in place (see [_adoptLegacyFile]).
  static const fileName = 'nexo.db';
  static const legacyFileName = 'expensy.db';
  static String? _directory;
  static bool _factoryConfigured = false;
  static Future<String>? _resolved;

  static Future<void> initialize({String? testDirectory}) async {
    _resolved = null;
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

  static Future<String> get path => _resolved ??= _resolve();

  static Future<String> _resolve() async {
    final dir = _directory ?? await getDatabasesPath();
    final target = p.join(dir, fileName);
    final legacy = p.join(dir, legacyFileName);
    if (await File(target).exists()) return target;
    if (!await File(legacy).exists()) return target;
    return await _adoptLegacyFile(legacy, target) ? target : legacy;
  }

  /// Renames the pre-1.12.9 file and its sidecars. The write-ahead log is
  /// folded into the main file first, so the rename moves every committed
  /// byte in one file. Returns false, with nothing moved, when the main file
  /// could not be renamed; the old name then keeps working as before.
  static Future<bool> _adoptLegacyFile(String legacy, String target) async {
    try {
      final db = await databaseFactory.openDatabase(legacy);
      try {
        await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      } finally {
        await db.close();
      }
      await File(legacy).rename(target);
    } catch (_) {
      return false;
    }
    for (final suffix in const ['-journal', '-wal', '-shm']) {
      final sidecar = File('$legacy$suffix');
      try {
        if (await sidecar.exists()) await sidecar.rename('$target$suffix');
      } catch (_) {
        // After the checkpoint a sidecar carries nothing; one left behind
        // under the old name is harmless.
      }
    }
    return true;
  }
}
