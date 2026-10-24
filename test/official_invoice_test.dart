import 'dart:io';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/screens/card_invoice_screen.dart';
import 'package:expensy/services/balance_check.dart';
import 'package:expensy/services/bank_snapshots.dart';
import 'package:expensy/services/billing_cycle.dart';
import 'package:expensy/services/official_invoice.dart';
import 'package:expensy/services/pluggy_inbox.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Remote implements PluggyRemote {
  _Remote(this.rows);
  final List<BankAccountSnapshot> rows;
  @override
  Future<List<BankAccountSnapshot>> accounts() async => rows;
  @override
  Future<void> link(String accountId, String? nexoAccountId) async {}
  @override
  Future<List<PluggyItem>> refresh({bool force = false}) async => const [];
  @override
  Future<List<PluggyItem>> items() async => const [];
  @override
  Future<void> addItem(String itemId, String label) async {}
  @override
  Future<void> removeItem(String itemId) async {}
  @override
  Future<List<Map<String, dynamic>>> suggestions(int sinceMs) async => const [];
  @override
  Future<void> decide(List<Map<String, Object?>> decisions) async {}
}

BankAccountSnapshot _card(List<BankBill> bills, {String? linkedTo = 'card'}) =>
    BankAccountSnapshot(
        accountId: 'p-card',
        bank: 'Banco fictício',
        type: 'CREDIT',
        name: 'Cartão',
        currency: 'BRL',
        nexoAccountId: linkedTo,
        bills: bills);

void main() {
  // Closing day 20, due day 27: the invoice that closes on 20/10.
  final october = BillingCycle.endingOn(DateTime(2026, 10, 20), 20, 27);

  test('server rows: essentials or nothing', () {
    final s = BankAccountSnapshot.fromJson({
      'account_id': 'p-card',
      'type': 'CREDIT',
      'bills': [
        {
          'bill_id': 'b1',
          'due_date': '2026-10-27',
          'close_date': null,
          'total_cents': 42092,
          'minimum_cents': 6314,
          'charges_cents': 350,
          'paid_cents': 0,
          'currency': 'BRL'
        },
        {'bill_id': 'b2', 'due_date': 'logo', 'total_cents': 1},
        'lixo',
      ],
    });
    expect(s.bills.map((b) => b.id), ['b1']);
    expect(s.bills.single.dueDate, DateTime(2026, 10, 27));
    expect(s.bills.single.chargesCents, 350);
    expect(
        BankAccountSnapshot.fromJson({'account_id': 'x', 'type': 'BANK'}).bills,
        isEmpty);
  });

  test('matched by closing date when the bank gives it, else by due date', () {
    final byClose = officialFor(
        _card([
          BankBill(
              id: 'set',
              dueDate: DateTime(2026, 9, 29),
              closeDate: DateTime(2026, 9, 21),
              totalCents: 100),
          BankBill(
              id: 'out',
              dueDate: DateTime(2026, 10, 29),
              closeDate: DateTime(2026, 10, 21),
              totalCents: 42092),
        ]),
        october,
        nexoTotal: 420.92,
        currency: 'BRL')!;
    expect(byClose.bill.id, 'out');
    expect(byClose.matches, isTrue);

    // Due moved by a weekend: still the same invoice; R$ 10 more in the bank.
    final byDue = officialFor(
        _card([
          BankBill(
              id: 'out', dueDate: DateTime(2026, 10, 28), totalCents: 61000)
        ]),
        october,
        nexoTotal: 600,
        currency: 'BRL')!;
    expect(byDue.differenceCents, 1000);
    expect(byDue.matches, isFalse);
  });

  test('no bank invoice: open cycle, other currency, far dates, not a card',
      () {
    final far = _card(
        [BankBill(id: 'x', dueDate: DateTime(2026, 11, 27), totalCents: 1)]);
    expect(officialFor(far, october, nexoTotal: 0, currency: 'BRL'), isNull);
    final usd = _card([
      BankBill(
          id: 'x',
          dueDate: DateTime(2026, 10, 27),
          totalCents: 1,
          currency: 'USD')
    ]);
    expect(officialFor(usd, october, nexoTotal: 0, currency: 'BRL'), isNull);
    expect(officialFor(null, october, nexoTotal: 0, currency: 'BRL'), isNull);
    final bank = BankAccountSnapshot(
        accountId: 'b',
        bank: 'B',
        type: 'BANK',
        name: 'n',
        currency: 'BRL',
        bills: [
          BankBill(id: 'x', dueDate: DateTime(2026, 10, 27), totalCents: 1)
        ]);
    expect(officialFor(bank, october, nexoTotal: 0, currency: 'BRL'), isNull);
  });

  testWidgets(
      'the invoice shows the bank total and the difference, hidden in privacy',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    PluggyInbox.instance = PluggyInbox(_Remote([
      _card([
        BankBill(
            id: 'out',
            dueDate: DateTime(2026, 10, 27),
            totalCents: 61000,
            minimumCents: 9150,
            chargesCents: 1000)
      ])
    ]));
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(
          (await Directory.systemTemp.createTemp('nexo-official-')).path);
      await DBHelper.database;
      await BankSnapshots.load(force: true);
    });
    final app = AppProvider()..settings.currency = 'BRL';
    app.accounts = [
      Account(
          id: 'card',
          name: 'Cartão teste',
          type: 'credit',
          balance: -600,
          colorValue: 0,
          currency: 'BRL',
          statementDay: 20,
          dueDay: 27)
    ];
    app.transactions = [
      AppTransaction(
          id: 'oct',
          type: 'expense',
          amount: 600,
          description: 'Compra outubro',
          accountId: 'card',
          categoryId: '',
          currency: 'BRL',
          date: DateTime(2026, 10, 1)),
    ];
    Future<void> show() async {
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              home: CardInvoiceScreen(
                  cardId: 'card', initialCycleEnd: DateTime(2026, 10, 20)))));
      for (var i = 0;
          i < 40 && find.text('Compra outubro').evaluate().isEmpty;
          i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)));
        await tester.pump();
      }
      await tester.pump();
    }

    await show();
    expect(find.textContaining('Fatura do banco'), findsOneWidget);
    expect(find.textContaining('a mais que o Nexo'), findsOneWidget);
    expect(find.textContaining('de encargos'), findsOneWidget);

    app.settings.hideBalance = true;
    await tester.pumpWidget(const SizedBox());
    await show();
    expect(find.textContaining('Fatura do banco'), findsNothing);

    // Not linked yet: the screen offers the link instead of guessing.
    app.settings.hideBalance = false;
    PluggyInbox.instance = PluggyInbox(_Remote([
      _card(
          [BankBill(id: 'out', dueDate: DateTime(2026, 10, 27), totalCents: 1)],
          linkedTo: null)
    ]));
    await tester.runAsync(() => BankSnapshots.load(force: true));
    await tester.pumpWidget(const SizedBox());
    await show();
    expect(find.textContaining('Fatura do banco'), findsNothing);
    expect(find.text('Vincular ao cartão do banco para ver a fatura oficial'),
        findsOneWidget);

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(DBHelper.close);
    PluggyInbox.instance = null;
    app.dispose();
  });
}
