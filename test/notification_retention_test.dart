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
    final dir = await Directory.systemTemp.createTemp('nexo-notification-test-');
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
    final start = DateTime(2026, 1, 1, 12);
    await NotificationInbox.ingest([suggestion('old', start)], now: start);
    expect(await NotificationInbox.pending(), hasLength(1));

    await NotificationInbox.ingest([], now: start.add(const Duration(days: 8)));
    final db = await DBHelper.database;
    final scrubbed = (await db.query('notification_suggestions',
            where: 'id = ?', whereArgs: ['old']))
        .single;
    expect(scrubbed['status'], 'expired');
    expect(scrubbed['description'], '');
    expect(scrubbed['amount_cents'], 0);

    await NotificationInbox.ingest([], now: start.add(const Duration(days: 91)));
    expect(
        await db.query('notification_suggestions',
            where: 'id = ?', whereArgs: ['old']),
        isEmpty);
  });
}
