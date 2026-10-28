import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/screens/finance_home_screen.dart';
import 'package:nexo/screens/analysis_screen.dart';
import 'package:nexo/screens/agenda_screen.dart';
import 'package:nexo/screens/add_transaction_screen.dart';
import 'package:nexo/services/transaction_metadata_service.dart';
import 'package:nexo/widgets/cash_timeline_chart.dart';
import 'package:nexo/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-home-tests-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
  });
  AppProvider fixture() {
    final app = AppProvider();
    app.settings.currency = 'BRL';
    app.settings.languageCode = 'pt';
    final now = DateTime.now();
    app.accounts = [
      Account(
          id: 'bank',
          name: 'Banco Teste',
          type: 'bank',
          balance: 2400,
          currency: 'BRL',
          colorValue: 0xff00695c)
    ];
    app.categories = [
      AppCategory(
          id: 'food',
          name: 'Alimentação',
          type: 'expense',
          colorValue: 0xff00695c)
    ];
    AppTransaction tx(String id, String desc, double value,
            {String type = 'expense', DateTime? date}) =>
        AppTransaction(
            id: id,
            description: desc,
            type: type,
            amount: value,
            accountId: 'bank',
            categoryId: 'food',
            date: date ?? now,
            currency: 'BRL');
    app.transactions = [
      tx('salary', 'Salário Teste', 1500, type: 'income'),
      tx('market', 'Mercado Teste', 100),
      tx('pending', 'Internet Teste', 80),
      tx('refund', 'Reembolso Teste', 20, type: 'income'),
      tx('past', 'Mercado passado', 200,
          date: DateTime(now.year, now.month - 1, 1))
    ];
    app.transactionMetadata = {
      'pending': TransactionMetadata(
          transactionId: 'pending',
          status: 'pending',
          dueDate: now.add(const Duration(days: 2))),
      'refund': const TransactionMetadata(
          transactionId: 'refund', source: 'notification_refund'),
    };
    app.budgets = [
      Budget(
          id: 'budget',
          categoryId: 'food',
          amount: 350,
          period: 'monthly',
          createdAt: now)
    ];
    return app;
  }

  Future<void> mount(WidgetTester tester, AppProvider app,
      {Size size = const Size(390, 844), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
                useMaterial3: true, colorSchemeSeed: const Color(0xff00695c)),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const FinanceHomeScreen())));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('No comparison bars without prior spending; review is accessible',
      (tester) async {
    final app = fixture();
    app.transactions.removeWhere((t) => t.id == 'past');
    await mount(tester, app);
    expect(find.text('Anterior'), findsNothing);
    expect(find.text('Sem base no período anterior para comparar'),
        findsOneWidget);
    expect(find.widgetWithText(ActionChip, 'Análises'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ActionChip, 'Análises'));
    await tester.tap(find.widgetWithText(ActionChip, 'Análises'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisScreen), findsOneWidget);
    expect(app.accounts.single.balance, 2400);
  });

  testWidgets(
      'Cash shortfall appears before monthly consumption and stays private',
      (tester) async {
    final app = fixture();
    app.accounts.single.balance = 50;
    await mount(tester, app);
    // The bill that the cash will not cover, with how much is missing.
    final warning = find.textContaining(RegExp(r'^Faltam .* para '));
    expect(warning, findsOneWidget);
    expect(find.text('Plano'), findsOneWidget);
    expect(tester.getTopLeft(warning).dy,
        lessThan(tester.getTopLeft(find.text('Entrou')).dy));
    expect(app.accounts.single.balance, 50);
    app.settings.hideBalance = true;
    await tester.pumpWidget(const SizedBox());
    await mount(tester, app);
    expect(warning, findsNothing);
  });

  testWidgets(
      'Month navigation changes consumption, not current balances; income excludes refunds',
      (tester) async {
    final app = fixture();
    await mount(tester, app);
    expect(find.text(formatAmount(2400, 'BRL')), findsWidgets);
    expect(find.text(formatAmount(1500, 'BRL')), findsWidgets);
    await tester.ensureVisible(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mês anterior'));
    await tester.pumpAndSettle();
    expect(find.text('Mês completo'), findsOneWidget);
    expect(find.text(formatAmount(2400, 'BRL')), findsWidgets);
    await tester.ensureVisible(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Próximo mês'));
    await tester.pumpAndSettle();
    expect(find.text('Até hoje'), findsOneWidget);
    await tester.ensureVisible(find.text('Entrou'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrou'));
    await tester.pumpAndSettle();
    expect(find.byType(AnalysisEntriesScreen), findsOneWidget);
    expect(find.text('Salário Teste'), findsOneWidget);
    expect(find.text('Reembolso Teste'), findsNothing);
    expect(app.accounts.single.balance, 2400);
    expect(app.transactions, hasLength(5));
  });
  testWidgets('Horizon carries into Agenda and no ledger entries are created',
      (tester) async {
    final app = fixture();
    await mount(tester, app);
    await tester.ensureVisible(find.text('90 dias'));
    await tester.tap(find.text('90 dias'));
    await tester.pumpAndSettle();
    final chart =
        tester.widget<CashTimelineChart>(find.byType(CashTimelineChart));
    expect(chart.timeline.points, hasLength(92));
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Agenda'));
    await tester.tap(find.widgetWithText(TextButton, 'Agenda'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(
        tester.widget<AgendaScreen>(find.byType(AgendaScreen)).initialDays, 90);
    expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '90 dias'))
            .selected,
        isTrue);
    expect(app.transactions, hasLength(5));
    expect(app.accounts.single.balance, 2400);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Private mode hides amounts, comparison bars and forecast chart',
      (tester) async {
    final app = fixture()..settings.hideBalance = true;
    await mount(tester, app);
    expect(find.byType(CashTimelineChart), findsNothing);
    expect(find.textContaining('R\$'), findsNothing);
    expect(find.textContaining('1.500'), findsNothing);
    expect(find.text('••••'), findsWidgets);
  });
  testWidgets(
      'Neutral movement cannot be repeated or edited as ordinary expense from Home',
      (tester) async {
    final app = fixture();
    final neutral = app.transactions.first;
    app.transactions = [neutral];
    app.transactionMetadata = {
      neutral.id: TransactionMetadata(
          transactionId: neutral.id,
          excludeFromSpending: true,
          source: 'transfer:pair')
    };
    await mount(tester, app);
    await tester.ensureVisible(find.text('Últimos lançamentos'));
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    await tester.ensureVisible(find.text(neutral.description));
    await tester.tap(find.text(neutral.description));
    await tester.pumpAndSettle();
    expect(find.byType(AddTransactionScreen), findsNothing);
    expect(app.transactions, hasLength(1));
  });
  for (final size in [
    const Size(320, 740),
    const Size(412, 915),
    const Size(1920, 1080)
  ]) {
    testWidgets('Home handles long labels and large amounts at $size',
        (tester) async {
      final app = fixture();
      app.accounts.single.balance = 123456789.99;
      app.transactions.first.amount = 123456789.99;
      app.transactions.first.description =
          'Descrição extensa para verificar legibilidade de lançamentos';
      await mount(tester, app, size: size, scale: size.width < 500 ? 1.5 : 1);
      await tester.ensureVisible(find.text('Últimos lançamentos'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
