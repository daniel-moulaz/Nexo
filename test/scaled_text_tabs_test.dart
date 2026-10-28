import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/screens/main_shell.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every tab of the phone bar, with data, at 412 px and 1.5× text: no
/// overflow and no exception. This is the guard the 1.12.7 overflow in
/// Recorrentes slipped past.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-scaled-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (_) async => true);
  });

  AppProvider fixture() {
    final now = DateTime.now();
    final app = AppProvider()
      ..settings.currency = 'BRL'
      ..settings.languageCode = 'pt'
      ..settings.userName = 'Alexandra Beatriz'
      ..settings.onboarded = true
      ..settings.budgetAlertsEnabled = false;
    app.accounts = [
      Account(
          id: 'main',
          name: 'Conta principal do banco',
          type: 'bank',
          balance: 4850.32,
          currency: 'BRL',
          colorValue: 0xff00695c),
      Account(
          id: 'card',
          name: 'Cartão roxo internacional',
          type: 'credit',
          balance: -1240.5,
          currency: 'BRL',
          colorValue: 0xff6750a4,
          statementDay: 3,
          dueDay: 10,
          creditLimit: 5000),
      Account(
          id: 'reserve',
          name: 'Reserva',
          type: 'savings',
          balance: 12400,
          currency: 'BRL',
          colorValue: 0xff1565c0),
    ];
    app.categories = [
      AppCategory(
          id: 'food', name: 'Alimentação', type: 'expense', colorValue: 1),
      AppCategory(id: 'home', name: 'Moradia', type: 'expense', colorValue: 2),
      AppCategory(
          id: 'subs', name: 'Assinaturas', type: 'expense', colorValue: 3),
      AppCategory(id: 'pay', name: 'Salário', type: 'income', colorValue: 4),
    ];
    AppTransaction tx(String id, String desc, double v, String cat,
            {String type = 'expense', String account = 'card', int ago = 0}) =>
        AppTransaction(
            id: id,
            type: type,
            amount: v,
            description: desc,
            accountId: account,
            categoryId: cat,
            date: now.subtract(Duration(days: ago)),
            currency: 'BRL');
    app.transactions = [
      tx('pay', 'Salário da empresa muito longa Ltda', 6200, 'pay',
          type: 'income', account: 'main', ago: 2),
      tx('rent', 'Aluguel do apartamento', 1650, 'home',
          account: 'main', ago: 1),
      tx('m1', 'Supermercado do bairro com nome comprido', 801.65, 'food'),
      tx('m2', 'Restaurante', 96.5, 'food', ago: 3),
      tx('s1', 'Streaming de filmes', 39.9, 'subs', ago: 5),
      tx('s2', 'Internet fibra', 99.9, 'subs', account: 'main', ago: 6),
      tx('old', 'Mercado do mês passado', 650, 'food', ago: 35),
    ];
    app.budgets = [
      Budget(
          id: 'b-food',
          categoryId: 'food',
          amount: 1200,
          period: 'monthly',
          createdAt: now.subtract(const Duration(days: 60))),
    ];
    app.savingsGoals = [
      SavingsGoal(
          id: 'trip',
          name: 'Viagem para o litoral',
          targetAmount: 8000,
          currentAmount: 3200,
          currency: 'BRL',
          colorValue: 0xffef6c00),
    ];
    return app;
  }

  for (final tab in const {
    'Hoje': 0,
    'Extrato': 8,
    'Orçamento': 4,
    'Investir': 11,
    'Contas': 3,
    'Mais': 5,
    'Recorrentes': 2,
    'Agenda': 7,
    'Análises': 6,
  }.entries) {
    testWidgets('${tab.key} holds at 412 px with 1.5× text', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = fixture();
      app.tabIndexNotifier.value = tab.value;
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: MaterialApp(
              locale: const Locale('pt'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              theme: ThemeData(useMaterial3: true),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.5)),
                  child: child!),
              home: const MainShell())));
      for (var i = 0; i < 12; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      app.dispose();
    });
  }
}
