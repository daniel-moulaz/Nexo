import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/investments/investment_models.dart';
import 'package:expensy/investments/investment_repository.dart';
import 'package:expensy/screens/investments_screen.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = InvestmentRepository();
  final boundary = GlobalKey();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-investments-ui-')).path);
    await initializeDateFormatting('pt_BR');
    if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
      await (FontLoader('ReviewFont')
            ..addFont(File('C:/Windows/Fonts/arial.ttf')
                .readAsBytes()
                .then((v) => ByteData.view(v.buffer))))
          .load();
      await (FontLoader('MaterialIcons')
            ..addFont(File(
                    'C:/Users/danie/develop/Flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
                .readAsBytes()
                .then((v) => ByteData.view(v.buffer))))
          .load();
    }
  });
  setUp(() async {
    final db = await DBHelper.database;
    await db.delete('investment_operations');
    await db.delete('investments');
  });
  tearDownAll(() async => DBHelper.close());
  Future<void> settle(WidgetTester tester) async {
    // SQLite FFI uses real async work; each chained query needs a frame to
    // resume before the next one can complete outside the fake test clock.
    for (var i = 0; i < 12; i++) {
      await tester.pump();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    await tester.pumpAndSettle();
  }

  Future<void> seed() async {
    for (var i = 0; i < 3; i++) {
      final item = Investment(
          id: 'asset$i',
          name: [
            'Empresa de demonstração',
            'Fundo de demonstração',
            'Título de demonstração'
          ][i],
          assetClass: investmentClasses[i],
          priceMicros: (30 + i * 10) * investmentScale,
          priceAt: DateTime(2026, 10, 1),
          ticker: i == 0 ? 'PETR4' : '',
          institution: 'Corretora de teste');
      await repo.create(
          item,
          InvestmentOperation(
              id: 'op$i',
              investmentId: item.id,
              kind: 'buy',
              quantity: 10 * investmentScale,
              cents: 20000,
              date: DateTime(2026, 10, 1),
              createdAt: DateTime(2026, 10, 1)));
    }
  }

  Future<AppProvider> mount(WidgetTester tester, Size size,
      {bool private = false, bool dark = false}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppProvider();
    app.settings.currency = 'BRL';
    app.settings.hideBalance = private;
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                fontFamily: const bool.fromEnvironment('CAPTURE_REVIEW')
                    ? 'ReviewFont'
                    : null),
            builder: (ctx, child) => MediaQuery(
                data: MediaQuery.of(ctx).copyWith(
                    textScaler: TextScaler.linear(size.width < 500 ? 1.2 : 1)),
                child: child!),
            home: RepaintBoundary(
                key: boundary, child: const InvestmentsScreen()))));
    await settle(tester);
    return app;
  }

  for (final size in [
    const Size(320, 740),
    const Size(412, 915),
    const Size(1280, 720),
    const Size(1920, 1080)
  ]) {
    testWidgets('portfolio responsive ${size.width}', (tester) async {
      await tester.runAsync(seed);
      await mount(tester, size, dark: size.width == 412);
      expect(find.text('Sua carteira · BRL'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
        await tester.runAsync(() async {
          final image = await (boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/investments-review').create(recursive: true);
          await File(
                  'build/investments-review/portfolio-${size.width.toInt()}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('privacy hides amounts and allocation; filters and details work',
      (tester) async {
    await tester.runAsync(seed);
    final app = await mount(tester, const Size(1280, 900), private: true);
    expect(find.text('Distribuição oculta no modo privado.'), findsOneWidget);
    expect(find.textContaining('R\$'), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(find.text('Ganho na posição'), findsNothing);
    expect(find.text('Perda na posição'), findsNothing);
    app.settings.hideBalance = false;
    app.notifyListeners();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Empresa');
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('investment-position-asset2')), findsNothing);
    await tester.ensureVisible(find.text('Empresa de demonstração'));
    await tester.tap(find.text('Empresa de demonstração'));
    await settle(tester);
    expect(find.text('Histórico'), findsOneWidget);
    expect(find.text('Informar preço'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'each asset shows signed change, remaining cost and no daily return',
      (tester) async {
    await tester.runAsync(() async {
      await seed();
      await repo.price(
          'asset1', 10 * investmentScale, DateTime.now(), 'manual');
      await repo.price(
          'asset2', 20 * investmentScale, DateTime.now(), 'manual');
    });
    await mount(tester, const Size(1280, 900));
    expect(find.text('+50,00%'), findsOneWidget);
    expect(find.text('−50,00%'), findsOneWidget);
    expect(find.text('0,00%'), findsWidgets);
    expect(find.text('Preço médio'), findsNWidgets(3));
    expect(find.text('Último preço'), findsNWidgets(3));
    final gain = tester.widget<Text>(find.text('+50,00%'));
    final loss = tester.widget<Text>(find.text('−50,00%'));
    expect(gain.style!.color, const Color(0xff146c43));
    expect(loss.style!.color, const Color(0xffb3261e));
    expect(tester.getTopLeft(find.text('Empresa de demonstração')).dy,
        lessThan(tester.getTopLeft(find.text('Distribuição por classe')).dy));
    expect(find.textContaining('Não é o rendimento do dia.'), findsOneWidget);
    expect(await tester.runAsync(() => DBHelper.getTransactions()), isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('zero cost never invents a percentage', (tester) async {
    await tester.runAsync(() async {
      final now = DateTime.now();
      await repo.create(
          Investment(
              id: 'free',
              name: 'Posição sem custo',
              assetClass: 'Ações',
              priceMicros: 10 * investmentScale,
              priceAt: now),
          InvestmentOperation(
              id: 'free-op',
              investmentId: 'free',
              kind: 'opening',
              quantity: investmentScale,
              cents: 0,
              date: now,
              createdAt: now));
    });
    await mount(tester, const Size(412, 915));
    expect(find.text('Sem base percentual'), findsNWidgets(2));
    expect(find.textContaining('Infinity'), findsNothing);
    expect(find.textContaining('NaN'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'create, sell and update price through UI persist without ledger changes',
      (tester) async {
    await mount(tester, const Size(1280, 900));
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Carteira sintética');
    await tester.enterText(fields.at(3), '10');
    await tester.enterText(fields.at(4), '100,00');
    await tester
        .ensureVisible(find.byKey(const ValueKey('investment-cash-account')));
    await tester.tap(find.byKey(const ValueKey('investment-cash-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Não movimentar conta (já registrado)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    final created = await tester.runAsync(() => repo.load());
    expect(created!.single.cost, 10000);
    await tester.pumpAndSettle();
    final positionCard = find
        .byKey(ValueKey('investment-position-${created.single.investment.id}'));
    await tester.ensureVisible(positionCard);
    await tester.pumpAndSettle();
    await tester.tap(positionCard);
    await settle(tester);
    await tester.tap(find.text('Registrar operação'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Venda / resgate').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), '30,00');
    await tester
        .ensureVisible(find.byKey(const ValueKey('investment-cash-account')));
    await tester.tap(find.byKey(const ValueKey('investment-cash-account')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Não movimentar conta (já registrado)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await settle(tester);
    await tester.tap(find.text('Informar preço'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '12,00');
    await tester.tap(find.text('Salvar preço'));
    await settle(tester);
    final after = await tester.runAsync(() => repo.load());
    expect(after!.single.quantity, 8 * investmentScale);
    expect(after.single.cost, 8000);
    expect(after.single.realized, 1000);
    expect(after.single.value, 9600);
    expect(await tester.runAsync(() => DBHelper.getTransactions()), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
