import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/screens/recurring_screen.dart';
import 'package:expensy/screens/recurring_detail_screen.dart';
import 'package:expensy/screens/debt_overview_screen.dart';
import 'package:expensy/screens/loans_screen.dart';
import 'package:expensy/screens/financial_checkup_screen.dart';
import 'package:expensy/services/transaction_metadata_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabasePlatform.initialize(
        testDirectory:
            (await Directory.systemTemp.createTemp('nexo-ux-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
    if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
      final font = FontLoader('ReviewFont')
        ..addFont(File('C:/Windows/Fonts/arial.ttf')
            .readAsBytes()
            .then((v) => ByteData.view(v.buffer)));
      await font.load();
    }
  });
  tearDownAll(DBHelper.close);
  AppProvider fixture() {
    final now = DateTime.now();
    final app = AppProvider();
    app.settings.currency = 'BRL';
    app.accounts = [
      Account(
          id: 'a',
          name: 'Banco de demonstração',
          type: 'bank',
          balance: 1000,
          currency: 'BRL',
          colorValue: 0),
      Account(
          id: 'c',
          name: 'Cartão de demonstração',
          type: 'credit',
          balance: -120,
          currency: 'BRL',
          colorValue: 0)
    ];
    app.recurring = [
      RecurringPayment(
          id: 'r',
          name: 'Compromisso demonstrativo com nome longo',
          accountId: 'a',
          categoryId: 'bills',
          amount: 123456.78,
          freqVal: 1,
          freqUnit: 'months',
          startDate: DateTime(now.year, now.month - 1, 1),
          nextDate: DateTime(now.year, now.month, 1),
          endDate: DateTime(now.year, now.month + 2, 1),
          paidPayments: 1),
      RecurringPayment(
          id: 'end',
          name: 'Cronograma antigo',
          accountId: 'a',
          categoryId: 'bills',
          amount: 10,
          freqVal: 1,
          freqUnit: 'months',
          startDate: DateTime(2020, 1, 1),
          nextDate: DateTime(2020, 2, 1),
          endDate: DateTime(2020, 1, 1),
          paidPayments: 1)
    ];
    app.loans = [
      Loan(
          id: 'l',
          name: 'Contrato de demonstração',
          principal: 1200,
          currency: 'BRL',
          startDate: DateTime(2026),
          endDate: DateTime(2027))
    ];
    app.transactions = [
      AppTransaction(
          id: 'p',
          type: 'expense',
          amount: 80,
          description: 'Despesa pendente',
          accountId: 'a',
          categoryId: 'bills',
          date: now)
    ];
    app.transactionMetadata = {
      'p': const TransactionMetadata(transactionId: 'p', status: 'pending')
    };
    return app;
  }

  Future<void> open(WidgetTester tester, AppProvider app, Widget screen,
      {double width = 360, double scale = 1, GlobalKey? boundary}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: ThemeData(
                useMaterial3: true,
                fontFamily: const bool.fromEnvironment('CAPTURE_REVIEW')
                    ? 'ReviewFont'
                    : null),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: RepaintBoundary(key: boundary, child: screen))));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
  }

  for (final width in [360.0, 412.0, 1280.0]) {
    for (final page in ['recurring', 'detail', 'debts', 'loans', 'checkup']) {
      testWidgets('$page visibility at $width with scaled text',
          (tester) async {
        final app = fixture();
        final boundary = GlobalKey();
        final screen = switch (page) {
          'recurring' => const RecurringScreen(),
          'detail' => RecurringDetailScreen(
              recurring: app.recurring.first, fmt: (v) => '$v'),
          'debts' => const DebtOverviewScreen(),
          'checkup' => const FinancialCheckupScreen(),
          _ => const LoansScreen()
        };
        await open(tester, app, screen,
            width: width, scale: width == 412 ? 1.5 : 1, boundary: boundary);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_REVIEW'))
          await tester.runAsync(() async {
            final img = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
            await File('build/review/ux_${page}_${width.toInt()}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            img.dispose();
          });
        await tester.pumpWidget(const SizedBox());
        app.dispose();
      });
    }
  }
  testWidgets(
      'Past, future and ended views never change ledger; cancel payment is safe',
      (tester) async {
    final app = fixture();
    await tester.runAsync(() => DBHelper.insertRecurringHistory(
        RecurringHistoryEntry(
            id: 'h',
            recurringId: 'r',
            action: 'paid',
            date: DateTime(2026, 1),
            amount: 75,
            currency: 'BRL')));
    await open(tester, app, const RecurringScreen());
    expect(find.text('Cronograma antigo'), findsNothing);
    await tester.tap(find.text('Próximos meses'));
    await tester.pumpAndSettle();
    expect(find.textContaining('não registra pagamentos'), findsOneWidget);
    await tester.tap(find.text('Histórico'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.textContaining('75,00'), findsWidgets);
    await tester.tap(find.text('Encerradas'));
    await tester.pumpAndSettle();
    expect(find.text('Cronograma antigo'), findsOneWidget);
    await tester.tap(find.text('Em aberto'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Registrar pagamento'), 300);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Registrar pagamento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registrar pagamento'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar registro?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(app.accounts.first.balance, 1000);
    expect(app.transactions, hasLength(1));
    expect(app.recurring.first.paidPayments, 1);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
  testWidgets('Privacy hides all amounts in recurring and debt views',
      (tester) async {
    for (final screen in [
      const RecurringScreen(),
      const DebtOverviewScreen(),
      const LoansScreen()
    ]) {
      final app = fixture()..settings.hideBalance = true;
      await open(tester, app, screen, width: 1280);
      expect(find.textContaining('R\$'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    }
  });
  testWidgets('Checkup generates locally and private mode blocks exports',
      (tester) async {
    final app = fixture();
    await open(tester, app, const FinancialCheckupScreen(), width: 412);
    await tester.tap(find.text('Gerar revisão'));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('O que aconteceu'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(app.accounts.first.balance, 1000);
    await tester.tap(find.text('Últimos 3 dias'));
    await tester.pumpAndSettle();
    expect(find.text('O que aconteceu'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.settings.hideBalance = true;
    await open(tester, app, const FinancialCheckupScreen());
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(find.text('Salvar relatório .txt'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    app.dispose();
  });
}
