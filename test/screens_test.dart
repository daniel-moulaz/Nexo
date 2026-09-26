import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/screens/accounts_screen.dart';
import 'package:expensy/screens/add_transaction_screen.dart';
import 'package:expensy/screens/budget_screen.dart';
import 'package:expensy/screens/recurring_screen.dart';
import 'package:expensy/screens/finance_home_screen.dart';
import 'package:expensy/screens/incomes_screen.dart';
import 'package:expensy/screens/expenses_v2_screen.dart';
import 'package:expensy/screens/more_screen.dart';
import 'package:expensy/screens/agenda_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    GoogleFonts.config.allowRuntimeFetching = false;
    if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
      final font = File('C:/Windows/Fonts/arial.ttf');
      if (await font.exists()) {
        final loader = FontLoader('ReviewFont')
          ..addFont(
              font.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)));
        await loader.load();
      }
    }
    await initializeDateFormatting('pt_BR');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-ui-test-')).path);
    await DBHelper.database;
  });
  for (final entry in <String, Widget>{
    'home': const FinanceHomeScreen(),
    'accounts': const AccountsScreen(),
    'budgets': const BudgetScreen(),
    'recurring': const RecurringScreen(),
    'expense_form': const AddTransactionScreen(),
    'income_form': const AddTransactionScreen(initialType: 'income'),
    'expenses': const ExpensesScreen(),
    'incomes': const IncomesScreen(),
    'more': const MoreScreen(),
    'agenda': const AgendaScreen(),
  }.entries) {
    testWidgets('${entry.key} fits a compact phone', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppProvider();
      app.settings.languageCode = 'pt';
      app.settings.currency = 'BRL';
      app.accounts = [
        Account(
            id: 'a',
            name: 'Banco principal',
            type: 'bank',
            balance: 3500,
            currency: 'BRL',
            colorValue: 0xff6750a4)
      ];
      app.categories = [
        AppCategory(
            id: 'bills',
            name: 'Moradia',
            type: 'expense',
            colorValue: 0xff6750a4),
        AppCategory(
            id: 'salary',
            name: 'Salário',
            type: 'income',
            colorValue: 0xff228833)
      ];
      app.budgets = [
        Budget(
            id: 'b',
            categoryId: 'bills',
            amount: 1000,
            period: 'monthly',
            createdAt: DateTime.now())
      ];
      app.transactions = [
        AppTransaction(
            id: 't',
            type: 'expense',
            amount: 250,
            description: 'Conta de energia',
            accountId: 'a',
            categoryId: 'bills',
            date: DateTime.now())
      ];
      app.recurring = [
        RecurringPayment(
            id: 'r',
            name: 'Internet residencial',
            accountId: 'a',
            categoryId: 'bills',
            amount: 100,
            freqVal: 1,
            freqUnit: 'months',
            startDate: DateTime.now(),
            nextDate: DateTime.now())
      ];
      final boundary = GlobalKey();
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
                fontFamily: const bool.fromEnvironment('CAPTURE_REVIEW')
                    ? 'ReviewFont'
                    : null,
                useMaterial3: true,
                colorSchemeSeed: const Color(0xff6750a4)),
            home: RepaintBoundary(key: boundary, child: entry.value),
          )));
      await tester.pump(const Duration(milliseconds: 500));
      final renderingError = tester.takeException();
      if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/review/${entry.key}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(renderingError, isNull);
      if (entry.key == 'recurring') {
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(find.text('Novo recorrente'), findsOneWidget);
        await tester.enterText(find.byType(TextField).at(0), 'Internet teste');
        await tester.enterText(find.byType(TextField).at(1), '1.234,56');
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await tester.tap(find.text('Salvar recorrente'));
          for (var i = 0;
              i < 200 && find.text('Salvar recorrente').evaluate().isNotEmpty;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump();
          }
        });
        await tester.pumpAndSettle();
        expect(
            app.recurring
                .any((r) => r.name == 'Internet teste' && r.amount == 1234.56),
            isTrue);
        expect(tester.takeException(), isNull);
      }
      if (entry.key == 'budgets') {
        await tester.tap(find.text('Adicionar orçamento'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, '1.234,56');
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
