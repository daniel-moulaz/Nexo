import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/screens/main_shell.dart';
import 'package:expensy/screens/investments_screen.dart';
import 'package:expensy/screens/transaction_search_screen.dart';
import 'package:expensy/screens/recurring_screen.dart';
import 'package:expensy/widgets/investment_market_info.dart';
import 'package:expensy/investments/investment_quotes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-nav-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDownAll(() => DBHelper.close());
  Future<void> mount(
      WidgetTester tester, AppProvider app, Widget child, double width) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: child)));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 180)));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 412.0]) {
    testWidgets('five destinations and grouped tools remain reachable $width',
        (tester) async {
      final app = AppProvider();
      await mount(tester, app, const MainShell(), width);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.destinations.length, 5);
      expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysShow);
      await tester.tap(find.text('Investir'));
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)));
      await tester.pumpAndSettle();
      expect(find.byType(InvestmentsScreen), findsOneWidget);
      expect(app.tabIndexNotifier.value, 11);
      await tester.tap(find.text('Extrato'));
      await tester.pumpAndSettle();
      expect(find.byType(TransactionSearchScreen), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).autofocus, false);
      await tester.tap(find.text('Mais').last);
      await tester.pumpAndSettle();
      expect(find.text('Planejar e acompanhar'), findsOneWidget);
      expect(find.text('Investimentos'), findsNothing);
      await tester.tap(find.text('Recorrentes e assinaturas'));
      await tester.pumpAndSettle();
      expect(find.byType(RecurringScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'cached market fields show separately and respect privacy offline',
      (tester) async {
    final date = DateTime(2026, 1, 2, 15);
    await MarketCache.save(
        'TEST3',
        MarketSnapshot.parse({
          'regularMarketChangePercent': -2.5,
          'regularMarketDayLow': 29,
          'logourl': 'https://icons.brapi.dev/icons/TEST3.svg',
        }, date));
    final app = AppProvider();
    await mount(
        tester,
        app,
        Scaffold(
            body: SingleChildScrollView(
                child: InvestmentMarketInfo(
                    ticker: 'TEST3', priceAt: date, expanded: true))),
        320);
    expect(find.text('-2,50% no pregão'), findsOneWidget);
    await tester.tap(find.text('Dados de mercado'));
    await tester.pumpAndSettle();
    expect(find.text('Não informado'), findsWidgets);
    expect(find.text('Mínima do pregão'), findsOneWidget);
    app.settings.hideBalance = true;
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(find.textContaining('%'), findsNothing);
    expect(find.textContaining('R\$'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
