import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/screens/add_transaction_screen.dart';
import 'package:nexo/screens/main_shell.dart';
import 'package:nexo/services/nexo_security.dart';
import 'package:nexo/widgets/command_palette.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-palette-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (_) async => true);
  });

  AppProvider fixture() {
    final app = AppProvider()
      ..settings.currency = 'BRL'
      ..settings.languageCode = 'pt'
      ..settings.onboarded = true;
    final now = DateTime.now();
    app.accounts = [
      Account(
          id: 'bank',
          name: 'Conta principal',
          type: 'bank',
          balance: 1000,
          currency: 'BRL',
          colorValue: 0xff00695c),
      Account(
          id: 'roxo',
          name: 'Cartão roxo',
          type: 'credit',
          balance: -200,
          currency: 'BRL',
          colorValue: 0xff6750a4),
    ];
    app.categories = [
      AppCategory(
          id: 'food', name: 'Alimentação', type: 'expense', colorValue: 1),
      AppCategory(id: 'pay', name: 'Salário', type: 'income', colorValue: 2),
    ];
    app.transactions = [
      AppTransaction(
          id: 't1',
          type: 'expense',
          amount: 45.9,
          description: 'Mercado Teste',
          accountId: 'roxo',
          categoryId: 'food',
          date: now,
          currency: 'BRL'),
      AppTransaction(
          id: 't2',
          type: 'income',
          amount: 6200,
          description: 'Salário Teste',
          accountId: 'bank',
          categoryId: 'pay',
          date: now,
          currency: 'BRL'),
    ];
    return app;
  }

  Future<void> mount(WidgetTester tester, AppProvider app, Widget home,
      {Size size = const Size(390, 844)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(useMaterial3: true),
            home: home)));
    // Database futures need real time before the frames settle.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  Widget opener() => Builder(
      builder: (context) => Scaffold(
          body: Center(
              child: TextButton(
                  onPressed: () => showCommandPalette(context),
                  child: const Text('abrir')))));

  testWidgets('a screen by name switches the tab', (tester) async {
    final app = fixture();
    await mount(tester, app, opener());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'agen');
    await tester.pumpAndSettle();
    expect(find.text('Agenda'), findsOneWidget);
    await tester.tap(find.text('Agenda'));
    await tester.pumpAndSettle();
    expect(app.tabIndexNotifier.value, 7);
    expect(find.byType(CommandPaletteView), findsNothing);
  });

  testWidgets('an entry by description opens it for editing', (tester) async {
    final app = fixture();
    await mount(tester, app, opener());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'merc');
    await tester.pumpAndSettle();
    expect(find.text('Mercado Teste'), findsOneWidget);
    expect(find.textContaining(RegExp(r'R\$.45,90')), findsOneWidget);
    await tester.tap(find.text('Mercado Teste'));
    await tester.pumpAndSettle();
    final form =
        tester.widget<AddTransactionScreen>(find.byType(AddTransactionScreen));
    expect(form.existing?.id, 't1');
  });

  testWidgets('a line with an amount opens the form filled in', (tester) async {
    final app = fixture();
    await mount(tester, app, opener());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), 'padaria 12,50 ontem no roxo');
    await tester.pumpAndSettle();
    expect(find.text('Lançar despesa'), findsOneWidget);
    expect(find.textContaining('Cartão roxo'), findsWidgets);
    await tester.tap(find.text('Lançar despesa'));
    await tester.pumpAndSettle();
    final form =
        tester.widget<AddTransactionScreen>(find.byType(AddTransactionScreen));
    expect(form.template?.amount, 12.5);
    expect(form.template?.description, 'Padaria');
    expect(form.template?.accountId, 'roxo');
    expect(form.template?.categoryId, 'food');
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    expect(form.initialDate?.day, yesterday.day);
    // The form shows the prefilled amount and description, ready to save.
    expect(find.widgetWithText(TextField, '12,50'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Padaria'), findsOneWidget);
    expect(app.transactions, hasLength(2), reason: 'nothing saved yet');
  });

  testWidgets('hidden balances stay hidden in the palette', (tester) async {
    final app = fixture()..settings.hideBalance = true;
    await mount(tester, app, opener());
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'conta');
    await tester.pumpAndSettle();
    expect(find.textContaining('R\$'), findsNothing);
    expect(find.textContaining('••••'), findsWidgets);
  });

  testWidgets('Ctrl+K opens the palette on the desktop shell', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    // Shortcuts only work on an unlocked, ready gate.
    NexoSecurity.instance
      ..ready = true
      ..locked = false;
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      NexoSecurity.instance
        ..ready = false
        ..locked = true;
    });
    final app = fixture();
    await mount(tester, app, const MainShell(), size: const Size(1280, 800));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(CommandPaletteView), findsOneWidget);
    expect(find.text('Ctrl+N'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'extrato');
    await tester.pumpAndSettle();
    await tester.testTextInput.receiveAction(TextInputAction.go);
    await tester.pumpAndSettle();
    expect(app.tabIndexNotifier.value, 8);
    expect(find.byType(CommandPaletteView), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
