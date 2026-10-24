import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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
    final empty = await DBHelper.exportAll();
    for (final key in empty.keys.toList()) {
      if (empty[key] is List) empty[key] = <Map<String, dynamic>>[];
    }
    await DBHelper.importAll(empty);
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
      null,
      'invalid',
      123,
      {1: 'invalid key'},
      suggestion('future', now.add(const Duration(days: 1))),
      {...suggestion('oversized', now), 'amount_cents': 100000000001},
      {...suggestion('description', now), 'description': 'x' * 81},
      {...suggestion('medium', now), 'medium': 'unsupported'},
    ], now: now);
    expect(await NotificationInbox.pending(), isEmpty);
  });
  test(
      'Synthetic intake survives malformed neighbors and replay without creating transactions',
      () async {
    final now = DateTime.now();
    final row = suggestion('synthetic', now);
    await NotificationInbox.ingest([null, row, 'broken', row], now: now);
    expect(await NotificationInbox.pending(), hasLength(1));
    final db = await DBHelper.database;
    expect(await db.query('transactions'), isEmpty);
    await NotificationInbox.ignore('synthetic');
    await NotificationInbox.ingest([row], now: now);
    expect(await NotificationInbox.pending(), isEmpty);
    expect(await db.query('transactions'), isEmpty);
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
  test('Concurrent sync waits for persistence and a failed ack safely replays',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(NotificationInbox.channel, null);
    });
    var failAck = true;
    var reads = 0;
    final row = suggestion('concurrent', DateTime.now());
    messenger.setMockMethodCallHandler(NotificationInbox.channel, (call) async {
      if (call.method == 'queue') {
        reads++;
        return jsonEncode([row]);
      }
      if (call.method == 'ack' && failAck) {
        throw PlatformException(code: 'ack_failed');
      }
      return null;
    });
    await expectLater(
        NotificationInbox.sync(), throwsA(isA<PlatformException>()));
    expect(await NotificationInbox.pending(), hasLength(1));
    failAck = false;
    final first = NotificationInbox.sync();
    final second = NotificationInbox.sync();
    await Future.wait([first, second]);
    expect(reads, greaterThanOrEqualTo(3));
    expect(await NotificationInbox.pending(), hasLength(1));
    expect(await (await DBHelper.database).query('transactions'), isEmpty);
  });
}
