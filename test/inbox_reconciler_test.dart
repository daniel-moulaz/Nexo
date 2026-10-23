import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/screens/notification_inbox_screen.dart';
import 'package:expensy/services/inbox_reconciler.dart';
import 'package:expensy/services/notification_inbox.dart';
import 'package:expensy/services/balance_check.dart';
import 'package:expensy/services/pluggy_inbox.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Server stand-in with the decision rules of `nexo_pluggy_decide`.
class _Remote implements PluggyRemote {
  @override
  Future<List<BankAccountSnapshot>> accounts() async => const [];
  @override
  Future<void> link(String accountId, String? nexoAccountId) async {}
  final rows = <String, Map<String, dynamic>>{};
  @override
  Future<List<PluggyItem>> refresh({bool force = false}) async => const [];
  @override
  Future<List<PluggyItem>> items() async => const [];
  @override
  Future<void> addItem(String itemId, String label) async {}
  @override
  Future<void> removeItem(String itemId) async {}
  @override
  Future<List<Map<String, dynamic>>> suggestions(int sinceMs) async =>
      [for (final r in rows.values) Map.of(r)];
  @override
  Future<void> decide(List<Map<String, Object?>> list) async {
    for (final d in list) {
      final row = rows[d['id']];
      if (row == null || row['review'] == 'confirmed') continue;
      if (d['review'] == 'pending' && row['review'] != 'ignored') continue;
      row['review'] = d['review'];
    }
  }

  void add(
          String id, int cents, String description, String kind, DateTime at) =>
      rows['pluggy:$id'] = {
        'id': 'pluggy:$id',
        'amount_cents': cents,
        'kind': kind,
        'medium': 'bank',
        'description': description,
        'occurred_at': at.millisecondsSinceEpoch,
        'review': 'pending',
      };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppProvider app;
  late _Remote remote;
  final today = DateTime.now();
  final at = DateTime(today.year, today.month, today.day, 12);

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-inbox-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
    app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.categories = await DBHelper.getCategories();
    await app.addAccount(Account(
        id: 'mp',
        name: 'Conta principal',
        type: 'bank',
        balance: 500,
        currency: 'BRL',
        colorValue: 0));
    await app.addTransaction(AppTransaction(
        id: 'lanche',
        type: 'expense',
        amount: 8,
        description: 'lanche ufop',
        accountId: 'mp',
        categoryId: 'food_exp',
        date: at));
    remote = _Remote()
      ..add('pix8', 800, 'Pagamento com Pix Fulana Aparecida', 'expense', at)
      ..add('acai', 3085, 'Ifd*Wesley', 'expense', at)
      ..add('r1', 500, 'Reserva por gasto MT', 'transfer', at)
      ..add('yield', 3, 'Rendimento', 'income', at)
      ..add('new', 1000, 'Pix enviado Beltrano', 'expense', at);
    await app.addTransaction(AppTransaction(
        id: 'acai-manual',
        type: 'expense',
        amount: 30,
        description: 'Açaí',
        accountId: 'mp',
        categoryId: 'food_exp',
        date: at));
    PluggyInbox.instance = PluggyInbox(remote);
  });

  tearDown(() async {
    PluggyInbox.instance = null;
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('the app resolves the boring part; the person decides the rest',
      (tester) async {
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NotificationInboxScreen())));
    // SQLite FFI work runs outside the fake clock: wait for the outcome
    // (bounded) instead of a fixed number of frames, so a busy machine
    // does not fail the test.
    Future<void> settle([Finder? until]) async {
      for (var i = 0; i < 150; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
        if (i >= 10 && (until == null || until.evaluate().isNotEmpty)) break;
      }
    }

    await settle(find.text('3 resolvida(s) automaticamente'));
    expect(tester.takeException(), isNull);
    // Linked (Pix = "lanche ufop"), reserve and tiny yield: automatic.
    expect(find.text('3 resolvida(s) automaticamente'), findsOneWidget);
    expect(find.text('Na dúvida'), findsOneWidget);
    expect(find.text('Novas'), findsOneWidget);
    final db = await tester.runAsync(() => DBHelper.database);
    final linked = await tester.runAsync(() => db!.query(
        'notification_suggestions',
        where: 'id = ?',
        whereArgs: ['pluggy:pix8']));
    expect(linked!.single['status'], 'confirmed');
    expect(linked.single['transaction_id'], 'lanche');
    // Nothing became money.
    expect((await tester.runAsync(DBHelper.getTransactions))!, hasLength(2));

    await tester.tap(find.text('É o mesmo'));
    await settle();
    expect(find.text('Na dúvida'), findsNothing);
    expect(find.text('4 resolvida(s) automaticamente'), findsNothing);

    // Undo the reserve: it comes back and the app leaves it to the person.
    await tester.tap(find.text('3 resolvida(s) automaticamente'));
    await settle();
    final undo = find.text('Desfazer');
    expect(undo, findsNWidgets(2)); // reserve and yield; the link is final
    await tester.tap(undo.first);
    await settle();
    final pending = await tester.runAsync(NotificationInbox.pending);
    expect(pending!.map((r) => r['id']),
        containsAll(['pluggy:new', isNot('pluggy:pix8')]));
    expect(pending.length, 2);
    final again = await tester.runAsync(() => InboxReconciler.run(
        pendingRows: pending,
        transactions: app.transactions,
        metadata: app.transactionMetadata));
    expect(again!.matches, hasLength(2), reason: 'undone stays manual');
    await tester.pumpWidget(const SizedBox());
    // Widget tests require debug overrides back to default before ending.
    debugDefaultTargetPlatformOverride = null;
  });
}
