import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/screens/analysis_screen.dart';
import 'package:nexo/screens/finance_home_screen.dart';
import 'package:nexo/screens/main_shell.dart';
import 'package:nexo/screens/transaction_search_screen.dart';
import 'package:nexo/screens/add_transaction_screen.dart';
import 'package:nexo/services/nexo_security.dart';
import 'package:flutter/foundation.dart';
import 'package:nexo/services/transaction_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-analysis-ui-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
    if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
      final loader = FontLoader('ReviewFont')
        ..addFont(File('C:/Windows/Fonts/arial.ttf')
            .readAsBytes()
            .then((b) => ByteData.view(b.buffer)));
      await loader.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(File(
                'C:/Users/danie/develop/Flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
            .readAsBytes()
            .then((b) => ByteData.view(b.buffer)));
      await icons.load();
    }
  });
  AppProvider fixture({bool includeCard = false}) {
    final app = AppProvider();
    app.settings.currency = 'BRL';
    app.settings.languageCode = 'pt';
    app.accounts = [
      Account(
          id: 'bank',
          name: 'Conta de demonstração',
          type: 'bank',
          balance: 2500,
          currency: 'BRL',
          colorValue: 0xff00695c),
      if (includeCard)
        Account(
            id: 'card',
            name: 'Cartão de demonstração',
            type: 'credit',
            balance: -600,
            currency: 'BRL',
            colorValue: 0xff6750a4,
            statementDay: 20,
            dueDay: 27,
            linkedAccountId: 'bank'),
    ];
    app.categories = [
      AppCategory(
          id: 'food',
          name: 'Alimentação',
          type: 'expense',
          colorValue: 0xff00695c),
      AppCategory(
          id: 'transport',
          name: 'Transporte',
          type: 'expense',
          colorValue: 0xffe65100)
    ];
    final now = DateTime.now();
    app.transactions = [
      for (var i = 0; i < 24; i++)
        AppTransaction(
            id: 'demo$i',
            type: 'expense',
            amount: i + 12.5,
            description: 'Compra demonstrativa $i',
            accountId: 'bank',
            categoryId: i.isEven ? 'food' : 'transport',
            date: DateTime(now.year, now.month, i % now.day + 1)),
      if (includeCard)
        AppTransaction(
            id: 'card-current',
            type: 'expense',
            amount: 400,
            description: 'Compra no cartão',
            accountId: 'card',
            categoryId: 'transport',
            date: now,
            currency: 'BRL'),
      if (includeCard)
        AppTransaction(
            id: 'card-prior',
            type: 'expense',
            amount: 200,
            description: 'Compra anterior no cartão',
            accountId: 'card',
            categoryId: 'transport',
            date: DateTime(now.year, now.month - 1, 1),
            currency: 'BRL'),
    ];
    app.transactionMetadata = {
      for (final t in app.transactions)
        t.id: TransactionMetadata(transactionId: t.id, subcategory: 'Exemplo')
    };
    app.budgets = [
      Budget(
          id: 'budget',
          categoryId: 'food',
          amount: 600,
          period: 'monthly',
          createdAt: now)
    ];
    return app;
  }

  for (final size in [
    const Size(360, 800),
    const Size(412, 915),
    const Size(1280, 720),
    const Size(1366, 768),
    const Size(1920, 1080),
    const Size(2560, 1440)
  ]) {
    for (final screen in [
      'home',
      'analysis',
      'closing',
      'shell',
      'transactions'
    ]) {
      testWidgets(
          '$screen ${size.width.toInt()} responsive with accessible text',
          (tester) async {
        if (size.width >= 900)
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = fixture(includeCard: screen == 'home' || screen == 'shell');
        final boundary = GlobalKey();
        final page = switch (screen) {
          'home' => const FinanceHomeScreen(),
          'analysis' => const AnalysisScreen(),
          'closing' => const AnalysisScreen(closing: true),
          'transactions' => const TransactionSearchScreen(),
          _ => const MainShell(),
        };
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: app,
            child: MaterialApp(
                locale: const Locale('pt'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ThemeData(
                    useMaterial3: true,
                    colorSchemeSeed: const Color(0xff00695c),
                    brightness:
                        size.width == 412 ? Brightness.dark : Brightness.light,
                    fontFamily: const bool.fromEnvironment('CAPTURE_REVIEW')
                        ? 'ReviewFont'
                        : null),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler:
                            TextScaler.linear(size.width == 412 ? 1.5 : 1)),
                    child: child!),
                home: RepaintBoundary(key: boundary, child: page))));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 120)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file =
                File('build/review/v15_${screen}_${size.width.toInt()}.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (screen == 'analysis') {
          await tester.tap(find.text('Filtros'));
          await tester.pumpAndSettle();
          expect(find.text('Filtrar análises'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Alimentação').first);
          await tester.tap(find.text('Alimentação').first);
          await tester.pumpAndSettle();
          expect(find.byType(AnalysisEntriesScreen), findsOneWidget);
          final expected = app.transactions
              .where((t) => t.categoryId == 'food')
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          expect(find.text(expected.first.description), findsOneWidget);
          expect(find.text('Compra demonstrativa 1'), findsNothing);
          expect(tester.takeException(), isNull);
        }
        if (screen == 'shell' && size.width >= 900) {
          expect(find.widgetWithText(ListTile, 'Hoje'), findsOneWidget);
          await tester.tap(find.text('Análises').first);
          await tester.pumpAndSettle();
          expect(find.byType(AnalysisScreen), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
  testWidgets('Desktop keyboard, persistent search and dynamic resize',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final security = NexoSecurity.instance;
    security.ready = true;
    security.locked = false;
    final app = fixture();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: const MainShell())));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    Future<void> chord(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    // Give the desktop shell a focused control before keyboard navigation.
    await tester.tap(find.text('Extrato'));
    await tester.pumpAndSettle();
    await chord(LogicalKeyboardKey.keyF);
    await tester.enterText(find.byType(TextField), 'Compra demonstrativa 8');
    await tester.pumpAndSettle();
    expect(find.text('1 lançamento'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    await tester.tap(find.widgetWithText(ListTile, 'Hoje'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Extrato'));
    await tester.pumpAndSettle();
    expect(find.text('1 lançamento'), findsOneWidget);
    for (final size in [
      const Size(960, 640),
      const Size(1366, 768),
      const Size(1920, 1080),
      const Size(2560, 1440)
    ]) {
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    security.locked = true;
    await chord(LogicalKeyboardKey.keyN);
    expect(find.byType(AddTransactionScreen), findsNothing);
    security.locked = false;
    await chord(LogicalKeyboardKey.keyN);
    expect(find.byType(AddTransactionScreen), findsOneWidget);
    await chord(LogicalKeyboardKey.keyN);
    expect(
        find.byType(AddTransactionScreen, skipOffstage: false), findsOneWidget);
    expect(app.transactions, hasLength(24));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AddTransactionScreen), findsNothing);
    expect(find.text('1 lançamento'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    security.ready = false;
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
      'Desktop table sorts, pages, edits and repeats without autosaving',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = fixture();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('pt'),
            home: const TransactionSearchScreen())));
    await tester.pumpAndSettle();
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows.length, 20);
    await tester.tap(find.byTooltip('Próxima página'));
    await tester.pumpAndSettle();
    expect(tester.widget<DataTable>(find.byType(DataTable)).rows.length, 4);
    expect(find.textContaining('Página 2 de 2'), findsOneWidget);
    await tester.tap(find.text('Descrição'));
    await tester.pumpAndSettle();
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.sortColumnIndex, 1);
    expect(table.sortAscending, isTrue);
    expect(find.textContaining('Página 1 de 2'), findsOneWidget);
    await tester.tap(find.text('Compra demonstrativa 0'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<AddTransactionScreen>(find.byType(AddTransactionScreen))
            .existing!
            .id,
        'demo0');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ações do lançamento').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repetir como novo…'));
    await tester.pumpAndSettle();
    final form =
        tester.widget<AddTransactionScreen>(find.byType(AddTransactionScreen));
    expect(form.existing, isNull);
    expect(form.template!.id, 'demo0');
    expect(app.transactions, hasLength(24));
    final amount = find.byType(TextField).first;
    await tester.enterText(amount, '0');
    final previousFocus = FocusManager.instance.primaryFocus;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus, isNot(previousFocus));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Informe um valor maior que zero.'), findsOneWidget);
    expect(app.transactions, hasLength(24));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AddTransactionScreen), findsNothing);
    expect(app.transactions, hasLength(24));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('Privacy hides charts and financial amounts', (tester) async {
    final app = fixture()..settings.hideBalance = true;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app, child: MaterialApp(home: const AnalysisScreen())));
    await tester.pumpAndSettle();
    expect(find.textContaining('R\$'), findsNothing);
    expect(find.text('Valores e distribuição ocultos no modo privado.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  tearDownAll(DBHelper.close);
}
