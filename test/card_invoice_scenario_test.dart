import 'dart:io';

import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/services/billing_cycle.dart';
import 'package:expensy/services/current_invoice_summary.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// The card of the October 2026 reconciliation session (fictitious names):
/// closes on the 19th, due on the 26th. The bank put the purchases of the
/// 19th in the November invoice; the Nexo must agree.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AppProvider app;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-invoice-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
    app = AppProvider()..settings.budgetAlertsEnabled = false;
    app.categories = await DBHelper.getCategories();
    await app.addAccount(Account(
        id: 'main',
        name: 'Conta principal',
        type: 'bank',
        balance: 1000,
        currency: 'BRL',
        colorValue: 0));
    await app.addAccount(Account(
        id: 'card',
        name: 'Cartão roxo',
        type: 'credit',
        balance: 0,
        currency: 'BRL',
        colorValue: 0,
        statementDay: 19,
        dueDay: 26,
        creditLimit: 650));
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> buy(String id, double amount, DateTime date) =>
      app.addTransaction(AppTransaction(
          id: id,
          type: 'expense',
          amount: amount,
          description: id,
          accountId: 'card',
          categoryId: 'food_exp',
          date: date));

  test('October R\$ 420,92, November R\$ 213,59, total R\$ 634,51', () async {
    // October invoice (19/09 to 18/10): R$ 450,92.
    await buy('Mercado do mês', 300, DateTime(2026, 9, 19, 10));
    await buy('Farmácia', 150.92, DateTime(2026, 10, 18, 21));
    // November invoice: the purchases of the 19th already belong to it.
    for (final (id, amount, day) in [
      ('Ifd*Restaurante A', 29.24, 19),
      ('Mp *Onibus', 39.90, 19),
      ('Ifd*Lanchonete B', 26.49, 19),
      ('Ifd*Doceria C', 17.99, 19),
      ('Ifoodcom', 26.42, 21),
      ('Ifd*Pizzaria D', 30.85, 21),
      ('Ifd*Comida E', 26.42, 21),
      ('Limite convertido em saldo', 16.28, 26),
    ]) {
      await buy(id, amount, DateTime(2026, 10, day, 12));
    }
    // R$ 30 paid on 21/10, after the closing: it pays the closed invoice.
    final october = BillingCycle.forDate(DateTime(2026, 10, 1), 19, 26);
    expect(october.end, DateTime(2026, 10, 19));
    expect(october.due, DateTime(2026, 10, 26));
    await app.addTransfer(
        fromId: 'main',
        toId: 'card',
        fromAmount: 30,
        invoiceCycleEnd: october.end,
        occurredAt: DateTime(2026, 10, 21, 9));
    // More than what is left of October is refused.
    await expectLater(
        app.addTransfer(
            fromId: 'main',
            toId: 'card',
            fromAmount: 421,
            invoiceCycleEnd: october.end),
        throwsA(isA<StateError>()));

    final payments =
        await (await DBHelper.database).query('card_invoice_payments');
    final card = app.accountById('card')!;
    double remaining(DateTime now) => currentInvoiceRemaining(
        card: card,
        now: now,
        transactions: app.transactions,
        metadata: app.transactionMetadata,
        payments: payments,
        convert: (v, _) => v);
    expect(remaining(DateTime(2026, 10, 18)), closeTo(420.92, 1e-9));
    expect(remaining(DateTime(2026, 10, 19)), closeTo(213.59, 1e-9));
    expect(remaining(DateTime(2026, 10, 21)), closeTo(213.59, 1e-9));
    expect(
        (await DBHelper.getAccounts())
            .firstWhere((a) => a.id == 'card')
            .balance,
        closeTo(-634.51, 1e-9));
  });

  test('a transfer has no spending category and is shown as one', () async {
    await app.addTransfer(fromId: 'main', toId: 'card', fromAmount: 10);
    final legs = await DBHelper.getTransactions();
    expect(legs, hasLength(2));
    for (final t in legs) {
      expect(t.categoryId, isEmpty);
      expect(app.categoryFor(t), isNull);
      expect(app.categoryLabel(t), 'Transferência');
    }
  });
}
