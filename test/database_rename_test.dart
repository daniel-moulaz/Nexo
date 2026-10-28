import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/database/database_platform.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Until 1.12.9 the local database was `expensy.db`. The first open after
/// the update must rename it, keep every row and never create a second,
/// empty database next to the old one.
void main() {
  late Directory root;
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('nexo-db-rename-');
    await DatabasePlatform.initialize(testDirectory: root.path);
  });
  tearDown(() => root.delete(recursive: true));

  test('a fresh install opens nexo.db', () async {
    expect(p.basename(await DatabasePlatform.path), DatabasePlatform.fileName);
    expect(File(p.join(root.path, 'expensy.db')).existsSync(), isFalse);
  });

  test('the old file is renamed in place with its rows and sidecars', () async {
    final legacy = p.join(root.path, 'expensy.db');
    final db = await databaseFactory.openDatabase(legacy);
    await db.execute('PRAGMA journal_mode=WAL');
    await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT)');
    await db.insert('t', {'v': 'kept'});
    await db.close();
    // A stale sidecar from an older journal mode must follow the file.
    await File('$legacy-journal').writeAsBytes(const []);

    final path = await DatabasePlatform.path;
    expect(p.basename(path), 'nexo.db');
    expect(File(legacy).existsSync(), isFalse);
    expect(File('$legacy-journal').existsSync(), isFalse);
    expect(File('$path-journal').existsSync(), isTrue);

    final moved = await databaseFactory.openDatabase(path);
    expect(await moved.query('t'), [
      {'id': 1, 'v': 'kept'}
    ]);
    await moved.close();

    // Asking again, even after a re-initialize, keeps the new name.
    await DatabasePlatform.initialize(testDirectory: root.path);
    expect(p.basename(await DatabasePlatform.path), 'nexo.db');
  });

  test('when both files exist the new one wins and the old is untouched',
      () async {
    for (final name in ['expensy.db', 'nexo.db']) {
      final db = await databaseFactory.openDatabase(p.join(root.path, name));
      await db.execute('CREATE TABLE t (v TEXT)');
      await db.insert('t', {'v': name});
      await db.close();
    }
    final path = await DatabasePlatform.path;
    expect(p.basename(path), 'nexo.db');
    expect(File(p.join(root.path, 'expensy.db')).existsSync(), isTrue);
    final db = await databaseFactory.openDatabase(path);
    expect((await db.query('t')).single['v'], 'nexo.db');
    await db.close();
  });
}
