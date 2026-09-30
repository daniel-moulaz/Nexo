import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/services/notification_inbox.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final dir =
        await Directory.systemTemp.createTemp('nexo-notification-test-');
    await databaseFactory.setDatabasesPath(dir.path);
  });

  setUp(() async {
    await DBHelper.importAll({'version': DBHelper.schemaVersion});
  });

  Map<String, dynamic> suggestion(String id, DateTime occurredAt) => {
        'id': id,
        'app_id': 'com.nu.production',
        'amount_cents': 3290,
        'description': 'IFOOD',
        'kind': 'expense',
        'medium': 'credit',
        'occurred_at': occurredAt.millisecondsSinceEpoch,
      };

  test('expired suggestion tombstones are scrubbed then pruned after 90 days',
      () async {
    // Keep the initial row inside the real 7-day production window. The
    // explicit `now` values below then advance cleanup deterministically.
    final start = DateTime.now().subtract(const Duration(minutes: 1));
    await NotificationInbox.ingest([suggestion('old', start)], now: start);
    final db = await DBHelper.database;
    expect(
        await db.query('notification_suggestions',
            where: 'id = ?', whereArgs: ['old']),
        hasLength(1));

    await NotificationInbox.ingest([], now: start.add(const Duration(days: 8)));
    final scrubbed = (await db.query('notification_suggestions',
            where: 'id = ?', whereArgs: ['old']))
        .single;
    expect(scrubbed['status'], 'expired');
    expect(scrubbed['description'], '');
    expect(scrubbed['amount_cents'], 0);

    await NotificationInbox.ingest([],
        now: start.add(const Duration(days: 91)));
    expect(
        await db.query('notification_suggestions',
            where: 'id = ?', whereArgs: ['old']),
        isEmpty);
  });
  test('Malformed future and oversized rows cannot become suggestions',
      () async {
    final now = DateTime.now();
    await NotificationInbox.ingest([
      suggestion('future', now.add(const Duration(days: 1))),
      {...suggestion('oversized', now), 'amount_cents': 100000000001},
      {...suggestion('description', now), 'description': 'x' * 81},
      {...suggestion('medium', now), 'medium': 'unsupported'},
    ], now: now);
    expect(await NotificationInbox.pending(), isEmpty);
  });
  test('Undo ignore cannot resurrect expired or confirmed rows', () async {
    final now = DateTime.now();
    await NotificationInbox.ingest([suggestion('undo', now)]);
    await NotificationInbox.ignore('undo');
    expect(await NotificationInbox.pending(), isEmpty);
    await NotificationInbox.undoIgnore('undo');
    expect(await NotificationInbox.pending(), hasLength(1));
    final db = await DBHelper.database;
    await db.update('notification_suggestions', {'status': 'confirmed'},
        where: 'id = ?', whereArgs: ['undo']);
    await NotificationInbox.undoIgnore('undo');
    expect(await NotificationInbox.pending(), isEmpty);
    await db.update(
        'notification_suggestions',
        {
          'status': 'ignored',
          'occurred_at':
              now.subtract(const Duration(days: 8)).millisecondsSinceEpoch
        },
        where: 'id = ?',
        whereArgs: ['undo']);
    await NotificationInbox.undoIgnore('undo');
    expect(await NotificationInbox.pending(), isEmpty);
  });
}
