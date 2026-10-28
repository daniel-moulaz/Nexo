import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/screens/envelopes_sheet.dart';
import 'package:nexo/services/envelopes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  AppCategory cat(String id, String name, {String? envelope}) => AppCategory(
      id: id, name: name, type: 'expense', colorValue: 0, envelope: envelope);
  AppTransaction tx(String id, double amount, String category,
          {DateTime? date, String type = 'expense'}) =>
      AppTransaction(
          id: id,
          type: type,
          amount: amount,
          description: id,
          accountId: 'a',
          categoryId: category,
          currency: 'BRL',
          date: date ?? DateTime(2026, 10, 10));
  final now = DateTime(2026, 10, 27);

  test('the default split is the AUVP method and sums 100', () {
    expect(defaultEnvelopeShares.values.fold<int>(0, (s, v) => s + v), 100);
    expect(defaultEnvelopeShares['freedom'], 25);
    expect(defaultEnvelopeShares['fixed'], 30);
  });

  test('a first guess from the category name', () {
    expect(suggestEnvelope('Moradia & Contas'), 'fixed');
    expect(suggestEnvelope('Alimentação'), 'fixed');
    expect(suggestEnvelope('Assinaturas'), 'comfort');
    expect(suggestEnvelope('Lazer'), 'pleasures');
    expect(suggestEnvelope('Educação'), 'knowledge');
    expect(suggestEnvelope('Investimentos'), 'freedom');
    expect(suggestEnvelope('Outros'), isNull);
  });

  test('the month against the shares; investing and saving count as done', () {
    final categories = [
      cat('rent', 'Moradia', envelope: 'fixed'),
      cat('food', 'Alimentação', envelope: 'fixed'),
      cat('fun', 'Lazer', envelope: 'pleasures'),
      cat('other', 'Outros'),
    ];
    final report = envelopeReport(
      categories: categories,
      transactions: [
        tx('rent', 1000, 'rent'),
        tx('market', 400, 'food'),
        tx('old', 999, 'food', date: DateTime(2026, 9, 10)),
        tx('bar', 120, 'fun'),
        tx('pending-but-counted', 30, 'fun'),
        tx('transfer', 500, 'other'),
        tx('misc', 80, 'other'),
        tx('salary', 5000, 'food', type: 'income'),
      ],
      metadata: {
        'transfer': const TransactionMetadata(
            transactionId: 'transfer',
            excludeFromSpending: true,
            source: 'transfer:x'),
      },
      contributions: [
        SavingsContribution(
            id: 'c1',
            goalId: 'g',
            amount: 300,
            accountId: 'a',
            type: 'deposit',
            date: DateTime(2026, 10, 5)),
        SavingsContribution(
            id: 'c2',
            goalId: 'g',
            amount: 100,
            accountId: 'a',
            type: 'withdraw',
            date: DateTime(2026, 10, 6)),
      ],
      investedCents: 125000,
      shares: defaultEnvelopeShares,
      referenceIncome: 5000,
      toMain: (t) => t.amount,
      now: now,
    );
    final byId = {for (final l in report.lines) l.def.id: l};
    expect(byId['fixed']!.planned, 1500);
    expect(byId['fixed']!.spent, 1400, reason: 'September stays out');
    expect(byId['fixed']!.over, isFalse);
    expect(byId['pleasures']!.spent, 150);
    expect(byId['pleasures']!.planned, 500);
    expect(byId['freedom']!.spent, 1250, reason: 'investment purchases');
    expect(byId['freedom']!.usedRatio, 1);
    expect(byId['freedom']!.over, isFalse, reason: 'investing is the goal');
    expect(byId['goals']!.spent, 300, reason: 'withdrawals do not count');
    expect(report.unassignedSpent, 80, reason: 'the transfer is neutral');
    expect(report.unassigned.map((c) => c.id), ['other']);
    expect(report.hasBase, isTrue);
    expect(report.spent, 1400 + 150 + 1250 + 300 + 80);
  });

  test('over the share is only for spending kinds', () {
    final report = envelopeReport(
      categories: [cat('fun', 'Lazer', envelope: 'pleasures')],
      transactions: [tx('party', 600, 'fun')],
      metadata: const {},
      contributions: const [],
      investedCents: 0,
      shares: defaultEnvelopeShares,
      referenceIncome: 5000,
      toMain: (t) => t.amount,
      now: now,
    );
    final fun = report.lines.firstWhere((l) => l.def.id == 'pleasures');
    expect(fun.over, isTrue);
    expect(fun.usedRatio, closeTo(1.2, 1e-9));
  });

  testWidgets(
      'the grid shows each kind, hides values in privacy, offers the link',
      (tester) async {
    final report = envelopeReport(
      categories: [
        cat('fun', 'Lazer', envelope: 'pleasures'),
        cat('x', 'Outros')
      ],
      transactions: [tx('party', 600, 'fun'), tx('misc', 10, 'x')],
      metadata: const {},
      contributions: const [],
      investedCents: 0,
      shares: defaultEnvelopeShares,
      referenceIncome: 5000,
      toMain: (t) => t.amount,
      now: now,
    );
    var adjust = 0, classify = 0;
    Widget build(bool hidden) => MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: EnvelopesView(
                    report: report,
                    money: (v) => 'R\$ ${v.toStringAsFixed(2)}',
                    hidden: hidden,
                    onAdjust: () => adjust++,
                    onClassify: () => classify++))));
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(build(false));
    expect(find.text('Por tipo de gasto'), findsOneWidget);
    expect(find.text('Prazeres'), findsOneWidget);
    expect(find.text('120% · passou'), findsOneWidget);
    expect(find.textContaining('1 categoria(s) sem tipo'), findsOneWidget);
    await tester.tap(find.text('Ajustar'));
    await tester.pump();
    await tester.ensureVisible(find.text('Classificar'));
    await tester.tap(find.text('Classificar'));
    await tester.pump();
    expect(adjust, 1);
    expect(classify, 1);
    await tester.pumpWidget(build(true));
    expect(find.textContaining('R\$ 600'), findsNothing);
    expect(find.text('•••• de ••••'), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}
