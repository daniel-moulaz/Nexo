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
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/screens/analysis_screen.dart';
import 'package:expensy/screens/finance_home_screen.dart';
import 'package:expensy/screens/main_shell.dart';
import 'package:expensy/screens/transaction_search_screen.dart';
import 'package:expensy/screens/add_transaction_screen.dart';
import 'package:expensy/services/nexo_security.dart';
import 'package:flutter/foundation.dart';
import 'package:expensy/services/transaction_metadata_service.dart';

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
  AppProvider fixture() {
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
          colorValue: 0xff00695c)
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
            date: DateTime(now.year, now.month, i % 10 + 1))
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
        final app = fixture();
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
          expect(find.text('Compra demonstrativa 8'), findsOneWidget);
          expect(find.text('Compra demonstrativa 1'), findsNothing);
          expect(tester.takeException(), isNull);
        }
        if (screen == 'shell' && size.width >= 900) {
          expect(find.text('Resumo'), findsOneWidget);
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
    await tester.tap(find.text('Transações'));
    await tester.pumpAndSettle();
    await chord(LogicalKeyboardKey.keyF);
    await tester.enterText(find.byType(TextField), 'Compra demonstrativa 8');
    await tester.pumpAndSettle();
    expect(find.text('1 resultado'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
    await tester.tap(find.text('Resumo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transações'));
    await tester.pumpAndSettle();
    expect(find.text('1 resultado'), findsOneWidget);
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
    expect(find.text('1 resultado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    security.ready = false;
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
