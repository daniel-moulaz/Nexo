import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/sync/assistant_commands.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Server queue stand-in with the claim/finish rules of the migration.
class _Queue implements AssistantRemote {
  final pending = <AssistantCommand>[];
  final finished = <String, (String, Map<String, Object?>)>{};

  void add(String id, String kind, Map<String, dynamic> args) =>
      pending.add(AssistantCommand(id, kind, args));

  @override
  Future<AssistantCommand?> claim(String datasetId, String deviceId) async =>
      pending.isEmpty ? null : pending.removeAt(0);

  @override
  Future<void> finish(
          String id, String status, Map<String, Object?> result) async =>
      finished[id] = (status, result);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Queue queue;
  late AppProvider app;
  late AssistantCommands assistant;

  Future<double> balance(String id) async =>
      (await DBHelper.getAccounts()).firstWhere((a) => a.id == id).balance;

  Future<void> run() =>
      assistant.run(datasetId: 'd', deviceId: 'device').then((_) {});

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-assistant-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
    app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.categories = await DBHelper.getCategories();
    for (final (id, balance) in [('bank', 1000.0), ('card', 0.0)]) {
      await app.addAccount(Account(
          id: id,
          name: id == 'bank' ? 'Banco fictício' : 'Carteira fictícia',
          type: 'bank',
          balance: balance,
          currency: 'BRL',
          colorValue: 0));
    }
    queue = _Queue();
    assistant = AssistantCommands(queue, app);
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Map<String, dynamic> expense([int cents = 3290]) => {
        'type': 'expense',
        'amount_cents': cents,
        'description': 'iFood',
        'account_id': 'bank',
        'category_id': 'food_exp',
        'date': '2026-10-20',
        'note': '',
      };

  test('a request becomes one transaction with the app rules', () async {
    queue.add('r1', 'transaction.add', expense());
    await run();
    expect(queue.finished['r1']!.$1, 'done');
    expect(await balance('bank'), closeTo(967.1, 1e-9));
    final t = (await DBHelper.getTransactions()).single;
    expect(t.id, 'assistant:r1');
    expect(t.date, DateTime(2026, 10, 20, 12));
  });

  test('a request offered again is never applied twice', () async {
    queue.add('r1', 'transaction.add', expense());
    await run();
    // The device stopped before the server heard back: offered again.
    queue.add('r1', 'transaction.add', expense());
    await run();
    expect((await DBHelper.getTransactions()).length, 1);
    expect(await balance('bank'), closeTo(967.1, 1e-9));
    expect(queue.finished['r1']!.$1, 'done');
  });

  test('transfer keeps the total; correction and deletion adjust balance',
      () async {
    queue.add('t', 'transfer.add', {
      'from_account_id': 'bank',
      'to_account_id': 'card',
      'amount_cents': 30000,
      'date': '2026-10-20',
      'note': 'reserva',
    });
    queue.add('e', 'transaction.add', expense());
    await run();
    expect(await balance('bank') + await balance('card'), closeTo(967.1, 1e-9));
    queue.add('u', 'transaction.update',
        {'id': 'assistant:e', 'amount_cents': 5000, 'category_id': 'shopping'});
    await run();
    expect(queue.finished['u']!.$1, 'done');
    expect(await balance('bank'), closeTo(650, 1e-9));
    final fixed = (await DBHelper.getTransactions())
        .firstWhere((t) => t.id == 'assistant:e');
    expect(fixed.categoryId, 'shopping');
    expect(fixed.description, 'iFood', reason: 'untouched fields stay');
    queue.add('d', 'transaction.delete', {'id': 'assistant:e'});
    queue.add('d2', 'transaction.delete', {'id': 'assistant:e'});
    await run();
    expect(await balance('bank'), closeTo(700, 1e-9));
    expect(queue.finished['d2']!.$2['message'], 'Já não existia.');
  });

  test('what the app refuses is reported, nothing changes', () async {
    queue.add('a', 'transaction.add', {...expense(), 'account_id': 'gone'});
    queue.add('c', 'transaction.add', {...expense(), 'category_id': 'gone'});
    queue.add('u', 'transaction.update', {'id': 'missing', 'amount_cents': 1});
    queue.add('x', 'money.send', {});
    await run();
    for (final id in ['a', 'c', 'u', 'x']) {
      expect(queue.finished[id]!.$1, 'rejected', reason: id);
      expect(queue.finished[id]!.$2['reason'], isNotEmpty);
    }
    expect(await DBHelper.getTransactions(), isEmpty);
    expect(await balance('bank'), 1000);
  });

  test('an Open Finance suggestion is confirmed through the inbox', () async {
    await (await DBHelper.database).insert('notification_suggestions', {
      'id': 'pluggy:s1',
      'app_id': 'pluggy',
      'amount_cents': 4590,
      'description': 'Mercado fictício',
      'kind': 'expense',
      'medium': 'bank',
      'occurred_at': DateTime.now()
          .subtract(const Duration(days: 3))
          .millisecondsSinceEpoch,
    });
    queue.add('s', 'suggestion.confirm',
        {'id': 'pluggy:s1', 'account_id': 'bank', 'category_id': 'food_exp'});
    queue.add('s2', 'suggestion.confirm',
        {'id': 'pluggy:s1', 'account_id': 'bank', 'category_id': 'food_exp'});
    await run();
    expect(queue.finished['s']!.$1, 'done');
    expect(queue.finished['s2']!.$2['message'], 'Já estava confirmada.');
    expect(
        (await DBHelper.getTransactions()).single.id, 'notification:pluggy:s1');
    expect(await balance('bank'), closeTo(954.1, 1e-9));
    final row = (await (await DBHelper.database).query(
            'notification_suggestions',
            where: 'id = ?',
            whereArgs: ['pluggy:s1']))
        .single;
    expect(row['status'], 'confirmed');
  });
}
