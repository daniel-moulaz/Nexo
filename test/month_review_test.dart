import 'package:expensy/models/models.dart';
import 'package:expensy/models/transaction_metadata.dart';
import 'package:expensy/services/month_review.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/screens/month_review_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

void main() {
  AppTransaction tx(String id, double amount, DateTime date,
          {String type = 'expense', String category = 'food'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: id,
          accountId: 'a',
          categoryId: category,
          date: date);

  final txs = [
    // September (previous month).
    tx('s-food', 300, DateTime(2026, 9, 10)),
    tx('s-fun', 100, DateTime(2026, 9, 12), category: 'fun'),
    // October.
    tx('recurring:salary:2026-10-05', 1500, DateTime(2026, 10, 5),
        type: 'income', category: 'pay'),
    tx('job', 100, DateTime(2026, 10, 8), type: 'income', category: 'pay'),
    tx('food1', 200, DateTime(2026, 10, 3)), // Saturday
    tx('food2', 150, DateTime(2026, 10, 10)), // Saturday
    tx('fun', 50, DateTime(2026, 10, 14), category: 'fun'),
    tx('move', 500, DateTime(2026, 10, 15)),
  ];
  final metadata = {
    'move': const TransactionMetadata(
        transactionId: 'move', excludeFromSpending: true, source: 'transfer:x'),
  };

  test('a closed month in highlights, against the month before', () {
    final r = MonthReview.build(
        transactions: txs,
        metadata: metadata,
        amount: (t) => t.amount,
        month: DateTime(2026, 10),
        now: DateTime(2026, 11, 2),
        budgetList: [
          Budget(
              id: 'b1',
              categoryId: 'food',
              amount: 300,
              period: 'monthly',
              createdAt: DateTime(2026, 1, 1)),
          // Created on the 16th: R$ 160 * 16/31 ≈ R$ 82,58; spent 0 since.
          Budget(
              id: 'b2',
              categoryId: 'fun',
              amount: 160,
              period: 'monthly',
              createdAt: DateTime(2026, 10, 16)),
        ]);
    expect(r.spent, 400);
    expect(r.previousSpent, 400);
    expect(r.change, 0);
    expect(r.fixedIncome, 1500);
    expect(r.extraIncome, 100);
    expect(r.result, 1200);
    expect(r.daysCounted, 31);
    expect(r.quietDays, 28);
    expect(r.topCategories().first, ('food', 350.0, 300.0));
    expect(r.biggest!.id, 'food1');
    expect(r.busiestWeekday, DateTime.saturday);
    expect(r.budgets.map((b) => b.$3), [300, closeTo(82.58, .01)]);
    expect(r.budgetsKept, 1); // food went over (350 of 300)
  });

  test('the current month counts only the days lived', () {
    final r = MonthReview.build(
        transactions: txs,
        metadata: metadata,
        amount: (t) => t.amount,
        month: DateTime(2026, 10),
        now: DateTime(2026, 10, 12));
    expect(r.daysCounted, 12);
    expect(r.spent, 350);
  });

  for (final hidden in [false, true]) {
    testWidgets('the screen fits a small phone (privacy: $hidden)',
        (tester) async {
      await initializeDateFormatting('pt_BR');
      tester.view.physicalSize = const Size(320, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppProvider()
        ..settings.currency = 'BRL'
        ..settings.languageCode = 'pt'
        ..settings.hideBalance = hidden
        ..transactions = txs
        ..transactionMetadata = metadata;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              locale: const Locale('pt'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: MonthReviewScreen(month: DateTime(2026, 10)))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Você gastou'), findsOneWidget);
      expect(find.text('Dias sem gastar'), findsOneWidget);
      bool money(Widget w) => w is Text && (w.data ?? '').contains('R\$');
      expect(
          find.byWidgetPredicate(money), hidden ? findsNothing : findsWidgets);
      await tester.tap(find.byTooltip('Mês anterior'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
