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
import 'package:expensy/screens/add_transaction_screen.dart';
import 'package:expensy/services/entry_suggestions.dart';

AppTransaction _tx(String id, String description, DateTime date,
        {String type = 'expense',
        String category = 'food',
        String account = 'bank'}) =>
    AppTransaction(
        id: id,
        type: type,
        amount: 10,
        description: description,
        accountId: account,
        categoryId: category,
        date: date);

void main() {
  group('similar entries', () {
    final txs = [
      _tx('1', 'Mercado Bom Preço', DateTime(2026, 10, 1)),
      _tx('2', 'mercado bom preço', DateTime(2026, 10, 15), category: 'home'),
      _tx('3', 'Supermercado', DateTime(2026, 10, 20)),
      _tx('4', 'Mercado', DateTime(2026, 10, 2), type: 'income'),
      _tx('5', 'Mercado reserva', DateTime(2026, 10, 3)),
      _tx('investment:6', 'Mercado de ações', DateTime(2026, 10, 4)),
    ];
    final meta = {
      '5': TransactionMetadata(transactionId: '5', excludeFromSpending: true)
    };

    test('one per description, most recent, prefix first', () {
      final r = similarEntries(txs, meta, 'merc', 'expense');
      expect(r.map((t) => t.id), ['2', '3']);
    });

    test('short text, the exact text and other types give nothing', () {
      expect(similarEntries(txs, meta, 'm', 'expense'), isEmpty);
      expect(similarEntries(txs, meta, 'Supermercado', 'expense'), isEmpty);
      expect(
          similarEntries(txs, meta, 'merc', 'income').map((t) => t.id), ['4']);
    });
  });

  group('form', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues({});
      await initializeDateFormatting('pt_BR');
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      await databaseFactory.setDatabasesPath(
          (await Directory.systemTemp.createTemp('nexo-form-ui-')).path);
      await DBHelper.database;
    });
    tearDownAll(DBHelper.close);

    testWidgets('a past entry fills category and account, never the amount',
        (tester) async {
      tester.view.physicalSize = const Size(360, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppProvider();
      app.settings.languageCode = 'pt';
      app.settings.currency = 'BRL';
      app.accounts = [
        Account(
            id: 'bank',
            name: 'Banco',
            type: 'bank',
            balance: 100,
            currency: 'BRL',
            colorValue: 0),
        Account(
            id: 'card',
            name: 'Cartão',
            type: 'credit',
            balance: 0,
            currency: 'BRL',
            colorValue: 0),
      ];
      app.categories = [
        AppCategory(
            id: 'fun', name: 'Lazer', type: 'expense', colorValue: 0xff3366cc),
        AppCategory(
            id: 'food',
            name: 'Alimentação',
            type: 'expense',
            colorValue: 0xffcc6633),
      ];
      app.transactions = [
        _tx('old', 'Padaria Central', DateTime.now(), account: 'card')
      ];
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              locale: const Locale('pt'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(useMaterial3: true),
              home: const AddTransactionScreen())));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Hoje'), findsOneWidget);
      expect(find.text('Ontem'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), 'pada');
      await tester.pump();
      final chip = find.text('Padaria Central · Alimentação');
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      expect(find.text('Padaria Central · Alimentação'), findsNothing);
      expect(
          tester
              .widget<ChoiceChip>(
                  find.widgetWithText(ChoiceChip, 'Alimentação'))
              .selected,
          isTrue);
      expect(find.text('Cartão • Cartão de crédito'), findsOneWidget);
      expect(
          tester
              .widget<TextField>(find.byType(TextField).first)
              .controller!
              .text,
          isEmpty);

      await tester.tap(find.text('Ontem'));
      await tester.pump();
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Ontem'))
              .selected,
          isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
