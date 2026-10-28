import 'dart:io';

import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/services/notification_inbox.dart';
import 'package:nexo/services/balance_check.dart';
import 'package:nexo/services/pluggy_inbox.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Server stand-in with the same decision rules as `nexo_pluggy_decide`.
class _Remote implements PluggyRemote {
  @override
  Future<List<BankAccountSnapshot>> accounts() async => const [];
  @override
  Future<void> link(String accountId, String? nexoAccountId) async {}
  final rows = <String, Map<String, dynamic>>{};
  final decisions = <Map<String, Object?>>[];
  int refreshes = 0;
  String? refreshFails;

  @override
  Future<List<PluggyItem>> refresh({bool force = false}) async {
    refreshes++;
    if (refreshFails != null) throw PluggyUnavailable(refreshFails!);
    return const [];
  }

  @override
  Future<List<PluggyItem>> items() async => const [];
  @override
  Future<void> addItem(String itemId, String label) async {}
  @override
  Future<void> removeItem(String itemId) async {}

  @override
  Future<List<Map<String, dynamic>>> suggestions(int sinceMs) async => [
        for (final r in rows.values)
          if ((r['occurred_at'] as int) >= sinceMs) Map.of(r)
      ];

  @override
  Future<void> decide(List<Map<String, Object?>> list) async {
    for (final d in list) {
      decisions.add(d);
      final row = rows[d['id']];
      if (row == null || row['review'] == 'confirmed') continue;
      if (d['review'] == 'pending' && row['review'] != 'ignored') continue;
      row['review'] = d['review'];
    }
  }

  void add(String id, int cents, DateTime at, {String review = 'pending'}) =>
      rows['pluggy:$id'] = {
        'id': 'pluggy:$id',
        'amount_cents': cents,
        'kind': 'expense',
        'medium': 'bank',
        'description': 'Mercado fictício $id',
        'occurred_at': at.millisecondsSinceEpoch,
        'review': review,
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Remote remote;
  late PluggyInbox inbox;
  var now = DateTime(2026, 10, 20, 12);

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-pluggy-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
    await DBHelper.database;
    now = DateTime.now();
    remote = _Remote();
    inbox = PluggyInbox(remote, now: () => now);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Future<List<String>> pendingIds() async =>
      [for (final r in await NotificationInbox.pending()) r['id'] as String];

  test('bank movements arrive for review and last 35 days, not 7', () async {
    remote.add('recent', 3290, now.subtract(const Duration(days: 1)));
    remote.add('twenty', 1500, now.subtract(const Duration(days: 20)));
    remote.add('old', 900, now.subtract(const Duration(days: 40)));
    expect(await inbox.sync(), null);
    expect(await pendingIds(), ['pluggy:recent', 'pluggy:twenty'],
        reason: 'the 7-day notification expiry does not apply');
    expect((await DBHelper.getTransactions()), isEmpty,
        reason: 'nothing becomes money by itself');
  });

  test('confirming registers once and tells the other devices', () async {
    await DBHelper.insertAccount(Account(
        id: 'bank',
        name: 'Banco fictício',
        type: 'bank',
        balance: 100,
        currency: 'BRL',
        colorValue: 0));
    remote.add('a', 3290, now.subtract(const Duration(days: 10)));
    await inbox.sync();
    final app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.accounts = await DBHelper.getAccounts();
    app.categories = await DBHelper.getCategories();
    await app.addTransaction(
        AppTransaction(
            id: 'notification:pluggy:a',
            type: 'expense',
            amount: 32.9,
            description: 'Mercado fictício a',
            accountId: 'bank',
            categoryId: 'food_exp',
            date: now.subtract(const Duration(days: 10)),
            currency: 'BRL'),
        suggestionId: 'pluggy:a');
    expect(await pendingIds(), isEmpty);
    expect((await DBHelper.getAccounts()).single.balance, closeTo(67.1, 1e-9));
    await inbox.sync();
    expect(remote.decisions.single, {
      'id': 'pluggy:a',
      'review': 'confirmed',
      'transaction_id': 'notification:pluggy:a'
    });
    expect(remote.rows['pluggy:a']!['review'], 'confirmed');
  });

  test('a suggestion resolved on another device leaves this inbox', () async {
    remote.add('x', 1000, now.subtract(const Duration(days: 2)));
    remote.add('y', 2000, now.subtract(const Duration(days: 2)));
    await inbox.sync();
    remote.rows['pluggy:x']!['review'] = 'confirmed';
    remote.rows['pluggy:y']!['review'] = 'ignored';
    await inbox.sync(force: true);
    expect(await pendingIds(), isEmpty);
  });

  test('the bank correcting a pending movement updates it', () async {
    remote.add('c', 1000, now.subtract(const Duration(days: 3)));
    await inbox.sync();
    remote.rows['pluggy:c']!['amount_cents'] = 1250;
    await inbox.sync(force: true);
    expect((await NotificationInbox.pending()).single['amount_cents'], 1250);
  });

  test('ignore, undo and the server decision stay consistent', () async {
    remote.add('i', 500, now.subtract(const Duration(days: 12)));
    await inbox.sync();
    await NotificationInbox.ignore('pluggy:i');
    await inbox.sync();
    expect(remote.rows['pluggy:i']!['review'], 'ignored');
    await NotificationInbox.undoIgnore('pluggy:i');
    await inbox.undoIgnore('pluggy:i');
    expect(remote.rows['pluggy:i']!['review'], 'pending');
    await inbox.sync(force: true);
    expect(await pendingIds(), ['pluggy:i'],
        reason: 'undo works within 35 days for Open Finance');
  });

  test('server problems are reported; stored suggestions still arrive',
      () async {
    remote.add('s', 700, now.subtract(const Duration(days: 1)));
    remote.refreshFails =
        'As credenciais do Pluggy ainda não foram cadastradas no servidor.';
    expect(await inbox.sync(), contains('credenciais'));
    expect(await pendingIds(), ['pluggy:s']);
  });

  test('the server is asked to read Pluggy at most every 30 minutes', () async {
    await inbox.sync();
    await inbox.sync();
    expect(remote.refreshes, 1);
    now = now.add(const Duration(minutes: 31));
    await inbox.sync();
    expect(remote.refreshes, 2);
    await inbox.sync(force: true);
    expect(remote.refreshes, 3);
  });

  test('opening the app brings bank data at most every 15 minutes, silently',
      () async {
    remote.add('o', 900, now.subtract(const Duration(hours: 2)));
    expect(await inbox.refreshInBackground(), isTrue);
    expect(await pendingIds(), ['pluggy:o']);
    expect(remote.refreshes, 1);
    remote.add('p', 400, now.subtract(const Duration(hours: 1)));
    expect(await inbox.refreshInBackground(), isFalse,
        reason: 'returning to the app right away does not read again');
    expect(await pendingIds(), ['pluggy:o']);
    now = now.add(const Duration(minutes: 16));
    remote.refreshFails = 'Servidor fora do ar.';
    expect(await inbox.refreshInBackground(), isTrue,
        reason: 'a server problem never reaches the person from here');
    expect(await pendingIds(), unorderedEquals(['pluggy:o', 'pluggy:p']));
  });

  test('bank notifications keep their 7-day expiry', () async {
    await NotificationInbox.ingest([
      {
        'id': 'n1',
        'app_id': 'com.nu.production',
        'amount_cents': 100,
        'description': 'Compra fictícia',
        'kind': 'expense',
        'medium': 'credit',
        'occurred_at': DateTime.now()
            .subtract(const Duration(days: 6))
            .millisecondsSinceEpoch,
      }
    ]);
    expect(await pendingIds(), ['n1']);
    await NotificationInbox.ingest([],
        now: DateTime.now().add(const Duration(days: 2)));
    expect(await pendingIds(), isEmpty);
  });
}
