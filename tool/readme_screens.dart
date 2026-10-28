// Renders the README screenshots from the real app widgets with fictitious
// data only (no profile, database or account of anyone).
//
//   flutter test tool/readme_screens.dart
//
// Writes docs/images/nexo-home-mobile.png and nexo-home-desktop.png. Needs
// Windows fonts (Segoe UI) and the Material icons from the Flutter cache.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:nexo/database/db_helper.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/models/transaction_metadata.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/screens/main_shell.dart';
import 'package:nexo/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

AppProvider _fixture() {
  final now = DateTime.now();
  DateTime day(int d) => DateTime(now.year, now.month, d.clamp(1, now.day));
  final app = AppProvider()
    ..settings.currency = 'BRL'
    ..settings.languageCode = 'pt'
    ..settings.userName = 'Alex'
    ..settings.onboarded = true
    ..settings.budgetAlertsEnabled = false;
  app.accounts = [
    Account(
        id: 'main',
        name: 'Conta principal',
        type: 'bank',
        balance: 4850.32,
        currency: 'BRL',
        colorValue: 0xff00695c),
    Account(
        id: 'reserve',
        name: 'Reserva',
        type: 'savings',
        balance: 12400,
        currency: 'BRL',
        colorValue: 0xff1565c0),
    Account(
        id: 'card',
        name: 'Cartão roxo',
        type: 'credit',
        balance: -1240.5,
        currency: 'BRL',
        colorValue: 0xff6a1b9a,
        statementDay: 19,
        dueDay: 26,
        creditLimit: 3000,
        linkedAccountId: 'main'),
  ];
  AppCategory cat(String id, String name, int color,
          [String type = 'expense']) =>
      AppCategory(id: id, name: name, type: type, colorValue: color);
  app.categories = [
    cat('food', 'Alimentação', 0xff2e7d32),
    cat('home', 'Moradia', 0xff1565c0),
    cat('transport', 'Transporte', 0xffef6c00),
    cat('fun', 'Lazer', 0xff8e24aa),
    cat('health', 'Saúde', 0xffc62828),
    cat('subs', 'Assinaturas', 0xff00838f),
    cat('salary', 'Salário', 0xff2e7d32, 'income'),
  ];
  var n = 0;
  AppTransaction tx(String desc, double amount, String category, int d,
          {String account = 'main', String type = 'expense'}) =>
      AppTransaction(
          id: 'demo${n++}',
          type: type,
          amount: amount,
          description: desc,
          accountId: account,
          categoryId: category,
          currency: 'BRL',
          date: day(d));
  app.transactions = [
    tx('Salário', 6200, 'salary', 5, type: 'income'),
    tx('Aluguel', 1650, 'home', 5),
    tx('Mercado da semana', 312.4, 'food', 6),
    tx('Padaria', 18.9, 'food', 7, account: 'card'),
    tx('Combustível', 210, 'transport', 8, account: 'card'),
    tx('Farmácia', 64.3, 'health', 9),
    tx('Cinema', 58, 'fun', 11, account: 'card'),
    tx('Mercado da semana', 287.15, 'food', 13),
    tx('Aplicativo de transporte', 32.7, 'transport', 14, account: 'card'),
    tx('Restaurante', 96.5, 'food', 16, account: 'card'),
    tx('Internet', 99.9, 'subs', 17),
    tx('Streaming', 39.9, 'subs', 18, account: 'card'),
    tx('Feira', 74.2, 'food', 20),
    tx('Academia', 119, 'health', 21),
    tx('Livraria', 67.8, 'fun', now.day, account: 'card'),
    tx('Café', 12.5, 'food', now.day, account: 'card'),
  ];
  app.transactionMetadata = {
    // Salary, rent and internet were paid through their recurring entries.
    for (final t in app.transactions)
      t.id: TransactionMetadata(
          transactionId: t.id,
          source:
              const {'Salário', 'Aluguel', 'Internet'}.contains(t.description)
                  ? 'recurring'
                  : 'manual')
  };
  app.recurring = [
    RecurringPayment(
        id: 'rent',
        name: 'Aluguel',
        accountId: 'main',
        categoryId: 'home',
        amount: 1650,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(now.year, now.month - 6, 5),
        nextDate: DateTime(now.year, now.month + 1, 5)),
    RecurringPayment(
        id: 'net',
        name: 'Internet',
        accountId: 'main',
        categoryId: 'subs',
        amount: 99.9,
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(now.year, now.month - 6, 17),
        nextDate: DateTime(now.year, now.month + 1, 17)),
    RecurringPayment(
        id: 'salary',
        name: 'Salário',
        accountId: 'main',
        categoryId: 'salary',
        amount: 6200,
        paymentType: 'income',
        freqVal: 1,
        freqUnit: 'months',
        startDate: DateTime(now.year, now.month - 6, 5),
        nextDate: DateTime(now.year, now.month + 1, 5)),
  ];
  app.budgets = [
    Budget(
        id: 'b-food',
        categoryId: 'food',
        amount: 1200,
        period: 'monthly',
        createdAt: DateTime(now.year, now.month - 2, 1)),
    Budget(
        id: 'b-fun',
        categoryId: 'fun',
        amount: 300,
        period: 'monthly',
        createdAt: DateTime(now.year, now.month - 2, 1)),
  ];
  app.savingsGoals = [
    SavingsGoal(
        id: 'trip',
        name: 'Viagem',
        targetAmount: 8000,
        currentAmount: 3200,
        currency: 'BRL',
        colorValue: 0xffef6c00),
  ];
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_tester runs from bin/cache/artifacts/engine/<platform>/.
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final icons = '${artifacts.path}/material_fonts/MaterialIcons-Regular.otf';

  setUpAll(() async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-readme-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
    const fonts = 'C:/Windows/Fonts';
    final segoe = [
      '$fonts/segoeui.ttf',
      '$fonts/seguisb.ttf',
      '$fonts/segoeuib.ttf'
    ];
    // Android screens ask for Roboto; Segoe UI stands in for it here.
    await _font('Segoe UI', segoe);
    await _font('Roboto', segoe);
    await _font('MaterialIcons', [icons]);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  for (final shot in [
    (
      name: 'nexo-home-mobile',
      size: const Size(412, 915),
      ratio: 2.0,
      desktop: false
    ),
    (
      name: 'nexo-home-desktop',
      size: const Size(1440, 900),
      ratio: 1.0,
      desktop: true
    ),
  ]) {
    testWidgets(shot.name, (tester) async {
      debugDefaultTargetPlatformOverride =
          shot.desktop ? TargetPlatform.windows : TargetPlatform.android;
      tester.view.physicalSize = shot.size * shot.ratio;
      tester.view.devicePixelRatio = shot.ratio;
      final app = _fixture();
      final boundary = GlobalKey();
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: app,
          child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                locale: const Locale('pt'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildTheme(seed: 'teal', dark: false),
                home: const MainShell()),
          )));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary)
            .toImage(pixelRatio: shot.ratio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/images/${shot.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }
}
