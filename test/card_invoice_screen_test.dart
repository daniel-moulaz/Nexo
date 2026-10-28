import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/screens/card_invoice_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'Changing invoice cannot display or pay the previous cycle while loading',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(
          (await Directory.systemTemp.createTemp('nexo-invoice-ui-')).path);
      await DBHelper.database;
    });
    final app = AppProvider()..settings.currency = 'BRL';
    app.accounts = [
      Account(
          id: 'card',
          name: 'Cartão teste',
          type: 'credit',
          balance: -800,
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
      AppTransaction(
          id: 'sep',
          type: 'expense',
          amount: 200,
          description: 'Compra setembro',
          accountId: 'card',
          categoryId: '',
          currency: 'BRL',
          date: DateTime(2026, 9, 1)),
    ];
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            home: CardInvoiceScreen(
                cardId: 'card', initialCycleEnd: DateTime(2026, 10, 20)))));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Compra outubro'), findsOneWidget);
    await tester.tap(find.byTooltip('Fatura anterior'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Registrar pagamento da fatura'), findsNothing);
    expect(find.text('Compra outubro'), findsNothing);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Compra setembro'), findsOneWidget);
    expect(find.text('Compra outubro'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(DBHelper.close);
    app.dispose();
  });
}
