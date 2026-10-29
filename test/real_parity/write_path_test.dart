// Write path on a COPY of the person's ledger (build/real_parity/copy, see
// real_parity_test.dart): the assistant's requests are applied with the
// app's rules, then undone, and the ledger must come back identical. Only
// table and column names are printed, never values.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/services/transaction_metadata_service.dart';
import 'package:nexo/sync/assistant_commands.dart';
import 'package:nexo/sync/ledger_capture.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Queue implements AssistantRemote {
  final pending = <AssistantCommand>[];
  final finished = <String, (String, Map<String, Object?>)>{};
  @override
  Future<AssistantCommand?> claim(String d, String dev) async =>
      pending.isEmpty ? null : pending.removeAt(0);
  @override
  Future<void> finish(String id, String s, Map<String, Object?> r) async =>
      finished[id] = (s, r);
  @override
  Future<void> report(String a, String b, String c, List<String> k,
      Map<String, Object?> s) async {}
  @override
  Future<void> markUndone(String id, String by) async {}
  @override
  Future<List<AssistantHistoryItem>> history(String d,
          {int limit = 50}) async =>
      const [];
  @override
  Future<Map<String, Object?>?> undoData(String id) async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Skipped unless a copy was placed there by hand (never in CI).
  final copy = File('build/real_parity/copy/nexo.db');
  test('real ledger copy: requests applied, then undone, leave it identical',
      skip: !copy.existsSync(), () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await DatabasePlatform.initialize(
        testDirectory: Directory('build/real_parity/copy').absolute.path);
    final db = await DBHelper.database;
    expect(await LedgerCapture.isInstalled(db), isTrue);

    Future<String> snapshot() async => jsonEncode({
          for (final e in ledgerTables.entries)
            e.key: [
              for (final r in await db.query(e.key, orderBy: e.value))
                {
                  ...r,
                  if (e.key == 'accounts')
                    'balance': ((r['balance'] as num) * 1e6).round()
                }
            ]
        });

    final app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.accounts = await DBHelper.getAccounts();
    app.categories = await DBHelper.getCategories();
    app.transactions = await DBHelper.getTransactions();
    app.transactionMetadata = await TransactionMetadataService.instance
        .getForMany(app.transactions.map((t) => t.id));
    app.recurring = await DBHelper.getRecurring();
    app.budgets = await DBHelper.getBudgets();
    app.savingsGoals = await DBHelper.getSavingsGoals();
    app.savingsContributions = await DBHelper.getAllSavingsContributions();
    await app.seedSharedSettings();
    final before = await snapshot();

    final queue = _Queue();
    final assistant = AssistantCommands(queue, app);
    final done = <String>[];
    Future<void> send(String id, String kind, Map<String, dynamic> args) async {
      queue.pending.add(AssistantCommand(id, kind, args));
      await assistant.run(datasetId: 'd', deviceId: 'copy');
      final (status, result) = queue.finished[id]!;
      // ignore: avoid_print
      print(
          '$kind: $status${status == 'rejected' ? ' (${result['reason']})' : ''}');
      if (status == 'done') done.add(id);
    }

    final unassigned = app.categories
        .where((c) => c.type == 'expense' && c.envelope == null)
        .take(2)
        .toList();
    await send('classify', 'category.envelope', {
      'assignments': [
        for (final c in unassigned) {'id': c.id, 'envelope': 'pleasures'}
      ]
    });
    await send('targets', 'settings.set', {
      'values': {'referenceIncome': 1800}
    });
    final adjust = app.categories
        .where((c) => c.name.toLowerCase().contains('ajuste'))
        .map((c) => c.id)
        .toSet();
    final old = app.transactions
        .where((t) =>
            adjust.contains(t.categoryId) &&
            !(app.transactionMetadata[t.id]?.isPending ?? false) &&
            !(app.transactionMetadata[t.id]?.source.startsWith('transfer:') ??
                false))
        .map((t) => t.id)
        .toList();
    if (old.isNotEmpty) {
      await send('neutral', 'transaction.neutralize', {'ids': old});
    }
    if (app.budgets.isNotEmpty) {
      final b = app.budgets.first;
      await send('budget', 'budget.save', {
        'id': b.id,
        'category_id': b.categoryId,
        'amount_cents': (b.amount * 100).round(),
        'period': b.period,
        'full_period': true,
      });
    }
    final balances = jsonEncode([
      for (final a in await db.query('accounts', orderBy: 'id')) a['balance']
    ]);
    expect((await snapshot()) != before, isTrue,
        reason: 'the requests changed it');

    for (final id in done.reversed.toList()) {
      queue.pending.add(AssistantCommand('undo-$id', 'request.undo', {
        'request_id': id,
        'undo': jsonDecode(jsonEncode(queue.finished[id]!.$2['undo'])),
      }));
      await assistant.run(datasetId: 'd', deviceId: 'copy');
      expect(queue.finished['undo-$id']!.$1, 'done', reason: 'undo $id');
    }
    final after = await snapshot();
    if (after != before) {
      final a = jsonDecode(before) as Map, b = jsonDecode(after) as Map;
      for (final t in a.keys) {
        final ra = {
          for (final r in a[t] as List) jsonEncode((r as Map).values.first): r
        };
        final rb = {
          for (final r in b[t] as List) jsonEncode((r as Map).values.first): r
        };
        final keys = {...ra.keys, ...rb.keys};
        for (final k in keys) {
          final x = ra[k], y = rb[k];
          if (x == null || y == null) {
            // ignore: avoid_print
            print('DIFF $t: row ${x == null ? 'added' : 'removed'}');
            continue;
          }
          final cols = [
            for (final c in x.keys)
              if (jsonEncode(x[c]) != jsonEncode(y[c])) c
          ];
          // ignore: avoid_print
          if (cols.isNotEmpty) print('DIFF $t: columns $cols');
        }
      }
    }
    expect(after == before, isTrue, reason: 'identical after undoing');
    // ignore: avoid_print
    print(
        'applied ${done.length}, undone ${done.length}; balances untouched by '
        'classification: ${balances == jsonEncode([
                  for (final a in await db.query('accounts', orderBy: 'id'))
                    a['balance']
                ])}');
  });
}
