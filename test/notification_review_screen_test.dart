import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/screens/notification_inbox_screen.dart';
import 'package:expensy/services/import_rules_service.dart';
import 'package:expensy/services/notification_inbox.dart';
import 'package:expensy/services/notification_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Remembered account and category prefill review but money changes only after confirmation',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (_) async => true);
    late AppProvider app;
    final row = {
      'id': 'synthetic-review',
      'app_id': 'test.bank',
      'amount_cents': 3290,
      'description': 'IFOOD',
      'kind': 'expense',
      'medium': 'bank',
      'occurred_at': DateTime.now().millisecondsSinceEpoch
    };
    final scope = NotificationPreferences.scope('test.bank', 'bank', 'expense');
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(
          (await Directory.systemTemp.createTemp('nexo-review-ui-')).path);
      app = AppProvider()..settings.currency = 'BRL';
      app.settings.budgetAlertsEnabled = false;
      final account = Account(
          id: 'bank',
          name: 'Conta de teste',
          type: 'bank',
          balance: 100,
          currency: 'BRL',
          colorValue: 0);
      final category = AppCategory(
          id: 'food', name: 'Alimentação', type: 'expense', colorValue: 0);
      await DBHelper.insertAccount(account);
      await DBHelper.insertCategory(category);
      app.accounts = [account];
      app.categories = [category];
      await NotificationPreferences.remember(scope, 'bank');
      await ImportRulesService.save(const ImportRule(
          id: 'ifood',
          pattern: 'IFOOD',
          type: 'expense',
          categoryId: 'food',
          subcategory: 'Delivery'));
      await NotificationInbox.ingest([row]);
    });
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    SuggestionReviewScreen(row: row))),
                        child: const Text('Abrir revisão')))))));
    await tester.tap(find.text('Abrir revisão'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Conta de teste'), findsOneWidget);
    expect(find.text('Alimentação'), findsOneWidget);
    expect(app.transactions, isEmpty);
    expect(app.accounts.single.balance, 100);
    await tester.ensureVisible(find.text('Lembrar esta escolha'));
    await tester.tap(find.text('Lembrar esta escolha'));
    await tester.pump();
    await tester.ensureVisible(find.text('Confirmar e registrar'));
    final reviewRoute =
        ModalRoute.of(tester.element(find.text('Confirmar e registrar')))!;
    await tester.runAsync(() async {
      await tester.tap(find.text('Confirmar e registrar'));
      for (var attempt = 0; attempt < 50 && reviewRoute.isCurrent; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    });
    await tester.pumpAndSettle();
    expect(app.transactions, hasLength(1),
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '));
    expect(app.accounts.single.balance, closeTo(67.1, 0.00001));
    expect(app.transactionMetadata.values.single.subcategory, 'Delivery');
    expect(find.text('Abrir revisão'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      expect(await NotificationInbox.pending(), isEmpty);
      expect((await NotificationPreferences.load())[scope], 'bank');
      await DBHelper.close();
    });
    await tester.pumpWidget(const SizedBox());
  });
}
