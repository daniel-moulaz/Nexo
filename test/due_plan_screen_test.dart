import 'dart:io';

import 'package:nexo/database/database_platform.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/models/models.dart';
import 'package:nexo/providers/app_provider.dart';
import 'package:nexo/screens/due_plan_screen.dart';
import 'package:nexo/services/cash_forecast.dart';
import 'package:nexo/services/liquidity.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;

  setUpAll(() async {
    await initializeDateFormatting('pt_BR');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    root = await Directory.systemTemp.createTemp('nexo-due-');
    await DBHelper.close();
    await DatabasePlatform.initialize(testDirectory: p.join(root.path, 'db'));
  });

  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await DBHelper.close();
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('session 2.10: R\$ 201,92 missing, the options and their timing',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppProvider()
      ..settings.currency = 'BRL'
      ..savingsGoals = [
        SavingsGoal(
            id: 'g',
            name: 'Reserva',
            targetAmount: 500,
            currentAmount: 50,
            currency: 'BRL',
            colorValue: 0)
      ];
    final due = DateTime.now().add(const Duration(days: 10));
    final shortfall = Shortfall(
        ForecastEvent(
            date: due,
            title: 'Fatura Cartão roxo',
            accountId: 'nu',
            kind: 'invoice',
            id: 'nu',
            currency: 'BRL',
            amount: -381.92),
        201.92,
        -201.92);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
            locale: const Locale('pt'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: DuePlanScreen(shortfall: shortfall))));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
      if (find.textContaining('Reserva ·').evaluate().isNotEmpty) break;
    }
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Faltam'), findsOneWidget);
    expect(find.textContaining('Na hora'), findsOneWidget);
    expect(find.textContaining('ainda faltariam'), findsOneWidget);
    expect(find.textContaining('rotativo'), findsOneWidget);
    expect(find.textContaining('aposta'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
