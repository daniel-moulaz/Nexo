import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/models/transaction_metadata.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/screens/budget_screen.dart';
import 'package:expensy/services/budget_insights.dart';

Budget _budget(double amount, {String period = 'monthly'}) => Budget(
    id: 'b',
    categoryId: 'food',
    amount: amount,
    period: period,
    createdAt: DateTime(2026));

AppTransaction _tx(String id, double amount, DateTime date,
        {String category = 'food', String type = 'expense'}) =>
    AppTransaction(
        id: id,
        type: type,
        amount: amount,
        description: id,
        accountId: 'a',
        categoryId: category,
        date: date);

void main() {
  group('budget pace', () {
    test('what is left is spread over the days left, today included', () {
      final p = budgetPace(_budget(900), 300, DateTime(2026, 10, 21));
      expect(p.daysLeft, 11); // 21..31
      expect(p.perDay, closeTo(600 / 11, 1e-9));
      expect(p.projection, closeTo(300 / 21 * 31, 1e-9));
    });

    test('over the limit leaves nothing per day', () {
      final p = budgetPace(_budget(100), 150, DateTime(2026, 10, 21));
      expect(p.perDay, 0);
    });

    test('no projection in the first days of the month', () {
      expect(budgetPace(_budget(100), 50, DateTime(2026, 10, 3)).projection,
          isNull);
    });

    test('weekly follows the week start setting', () {
      // 21/10/2026 is a Wednesday.
      final monday = budgetPace(
          _budget(70, period: 'weekly'), 0, DateTime(2026, 10, 21),
          weekStart: 'monday');
      final sunday = budgetPace(
          _budget(70, period: 'weekly'), 0, DateTime(2026, 10, 21),
          weekStart: 'sunday');
      expect(monday.daysLeft, 5); // Wed..Sun
      expect(sunday.daysLeft, 4); // Wed..Sat
      expect(monday.projection, isNull);
    });
  });

  group('budget suggestions', () {
    final categories = [
      AppCategory(id: 'food', name: 'Mercado', type: 'expense', colorValue: 0),
      AppCategory(id: 'fun', name: 'Lazer', type: 'expense', colorValue: 0),
      AppCategory(id: 'trip', name: 'Viagem', type: 'expense', colorValue: 0),
      AppCategory(id: 'move', name: 'Reserva', type: 'expense', colorValue: 0),
      AppCategory(id: 'pay', name: 'Salário', type: 'income', colorValue: 0),
    ];
    final now = DateTime(2026, 10, 21);
    List<BudgetSuggestion> run(List<AppTransaction> txs,
            {List<Budget> budgets = const [],
            Map<String, TransactionMetadata> metadata = const {}}) =>
        suggestBudgets(
            transactions: txs,
            metadata: metadata,
            categories: categories,
            budgets: budgets,
            toMain: (t) => t.amount,
            now: now);

    test('regular spending becomes a rounded limit, biggest first', () {
      final s = run([
        for (final m in [7, 8, 9]) _tx('f$m', 610, DateTime(2026, m, 10)),
        for (final m in [8, 9])
          _tx('l$m', 150, DateTime(2026, m, 5), category: 'fun'),
        // The current month is not a full month yet.
        _tx('now', 5000, DateTime(2026, 10, 2)),
      ]);
      expect(s.map((x) => x.category.id), ['food', 'fun']);
      expect(s.first.average, closeTo(610, 1e-9));
      expect(s.first.amount, 650);
      expect(s.last.amount, 100); // 300 / 3
    });

    test('a purchase marked as one-off does not raise the average', () {
      final s = run([
        for (final m in [7, 8, 9]) _tx('f$m', 600, DateTime(2026, m, 10)),
        _tx('party', 1500, DateTime(2026, 9, 20)),
      ], metadata: {
        'party': const TransactionMetadata(
            transactionId: 'party', expenseClass: 'extraordinary'),
      });
      expect(s.single.average, closeTo(600, 1e-9));
    });

    test('one-off, budgeted and neutral spending are not suggested', () {
      final s = run([
        _tx('trip', 3000, DateTime(2026, 8, 1), category: 'trip'),
        for (final m in [7, 8, 9]) _tx('f$m', 400, DateTime(2026, m, 10)),
        for (final m in [7, 8, 9])
          _tx('r$m', 500, DateTime(2026, m, 10), category: 'move'),
      ], budgets: [
        _budget(400)
      ], metadata: {
        for (final m in [7, 8, 9])
          'r$m': TransactionMetadata(
              transactionId: 'r$m', excludeFromSpending: true),
      });
      expect(s, isEmpty);
    });
  });

  group('goal monthly amount', () {
    SavingsGoal goal(double target, double saved, DateTime? date) =>
        SavingsGoal(
            id: 'g',
            name: 'Reserva',
            targetAmount: target,
            currentAmount: saved,
            currency: 'BRL',
            targetDate: date,
            colorValue: 0);

    test('spreads what is missing over the months until the date', () {
      // Oct (rest), Nov, Dec, Jan: four deposits until 31/01.
      expect(
          goalMonthlyNeeded(
              goal(5000, 1000, DateTime(2027, 1, 31)), DateTime(2026, 10, 21)),
          1000);
    });

    test('no date, reached or a past date asks for everything now', () {
      final now = DateTime(2026, 10, 21);
      expect(goalMonthlyNeeded(goal(5000, 1000, null), now), isNull);
      expect(
          goalMonthlyNeeded(goal(5000, 5000, DateTime(2027, 1, 1)), now), null);
      expect(
          goalMonthlyNeeded(goal(5000, 1000, DateTime(2026, 9, 1)), now), 4000);
    });
  });

  group('planning screen', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await initializeDateFormatting('pt_BR');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(
          (await Directory.systemTemp.createTemp('nexo-budget-ui-')).path);
      await DBHelper.database;
    });
    tearDownAll(DBHelper.close);

    Future<AppProvider> pump(WidgetTester tester, {bool hidden = false}) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final now = DateTime.now();
      final app = AppProvider();
      app.settings.languageCode = 'pt';
      app.settings.currency = 'BRL';
      app.settings.hideBalance = hidden;
      app.accounts = [
        Account(
            id: 'a',
            name: 'Banco',
            type: 'bank',
            balance: 1000,
            currency: 'BRL',
            colorValue: 0)
      ];
      app.categories = [
        AppCategory(
            id: 'food', name: 'Mercado', type: 'expense', colorValue: 0),
        AppCategory(
            id: 'fun',
            name: 'Lazer e passeios',
            type: 'expense',
            colorValue: 0),
      ];
      app.budgets = [_budget(500)];
      app.transactions = [
        _tx('t', 620.55, now),
        for (var m = 1; m <= 3; m++)
          _tx('l$m', 180, DateTime(now.year, now.month - m, 3),
              category: 'fun'),
      ];
      app.savingsGoals = [
        SavingsGoal(
            id: 'g',
            name: 'Reserva de emergência com nome comprido',
            targetAmount: 12000,
            currentAmount: 4321.09,
            currency: 'BRL',
            targetDate: DateTime(now.year + 1, now.month, 28),
            colorValue: 0xff228833)
      ];
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              locale: const Locale('pt'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(
                  useMaterial3: true, colorSchemeSeed: const Color(0xff6750a4)),
              home: const BudgetScreen())));
      await tester.pump(const Duration(milliseconds: 300));
      return app;
    }

    testWidgets('budgets show the limit, the overflow and a suggestion',
        (tester) async {
      await pump(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Orçado no mês'), findsOneWidget);
      expect(find.textContaining('do limite'), findsWidgets);
      // Suggestions sit below the envelopes and the budgets: scroll to them.
      await tester.scrollUntilVisible(find.text('Lazer e passeios'), 300,
          scrollable: find
              .descendant(
                  of: find.byType(ListView).first,
                  matching: find.byType(Scrollable))
              .first);
      expect(find.text('Lazer e passeios'), findsOneWidget);
      expect(find.textContaining('Limitar a'), findsOneWidget);

      await tester.tap(find.text('Objetivos'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Total guardado'), findsOneWidget);
      expect(find.textContaining('/mês até'), findsOneWidget);
    });

    testWidgets('privacy mode hides every amount', (tester) async {
      await pump(tester, hidden: true);
      bool money(Widget w) =>
          (w is Text && (w.data ?? '').contains('R\$')) ||
          (w is RichText && w.text.toPlainText().contains('R\$'));
      expect(find.byWidgetPredicate(money), findsNothing);
      await tester.tap(find.text('Objetivos'));
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate(money), findsNothing);
    });
  });
}
