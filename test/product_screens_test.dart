import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/l10n/app_localizations.dart';
import 'package:expensy/services/transaction_metadata_service.dart';
import 'package:expensy/screens/agenda_screen.dart';
import 'package:expensy/screens/import_rules_screen.dart';
import 'package:expensy/screens/transaction_search_screen.dart';
import 'package:expensy/screens/finance_export_screen.dart';
import 'package:expensy/screens/financial_planning_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-product-ui-')).path);
    await DBHelper.database;
    await initializeDateFormatting('pt_BR');
    if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
      final loader = FontLoader('ReviewFont')
        ..addFont(File('C:/Windows/Fonts/arial.ttf')
            .readAsBytes()
            .then((v) => ByteData.view(v.buffer)));
      await loader.load();
    }
  });
  for (final scenario in ['empty', 'many', 'dark']) {
    for (final entry in <String, Widget>{
      'forecast': const AgendaScreen(),
      'planning': const FinancialPlanningScreen(),
      'search': const TransactionSearchScreen(),
      'rules': const ImportRulesScreen(),
      'export': const FinanceExportScreen()
    }.entries) {
      testWidgets('${entry.key} $scenario responsive and accessible',
          (tester) async {
        tester.view.physicalSize =
            scenario == 'dark' ? const Size(412, 915) : const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = AppProvider();
        app.settings.currency = 'BRL';
        app.settings.languageCode = 'pt';
        app.settings.hideBalance = scenario == 'dark';
        app.categories = [
          AppCategory(
              id: 'bills',
              name: 'Casa e compromissos',
              type: 'expense',
              colorValue: 0)
        ];
        app.accounts = [
          Account(
              id: 'bank',
              name: 'Conta com nome comprido para validar a legibilidade',
              type: 'bank',
              balance: 1234567.89,
              currency: 'BRL',
              colorValue: 0)
        ];
        if (scenario != 'empty') {
          app.transactions = List.generate(
              40,
              (i) => AppTransaction(
                  id: 't$i',
                  type: 'expense',
                  amount: 987654.32,
                  description: 'Lançamento com descrição longa de teste $i',
                  accountId: 'bank',
                  categoryId: 'bills',
                  date: DateTime.now()));
          app.transactionMetadata = {
            for (final t in app.transactions)
              t.id: TransactionMetadata(
                  transactionId: t.id,
                  status: 'pending',
                  dueDate: DateTime.now())
          };
        }
        final boundary = GlobalKey();
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: app,
            child: MaterialApp(
                locale: const Locale('pt'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ThemeData(
                    brightness:
                        scenario == 'dark' ? Brightness.dark : Brightness.light,
                    fontFamily: const bool.fromEnvironment('CAPTURE_REVIEW')
                        ? 'ReviewFont'
                        : null),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler:
                            TextScaler.linear(scenario == 'empty' ? 1 : 1.5)),
                    child: child!),
                home: RepaintBoundary(key: boundary, child: entry.value))));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        if (entry.key == 'forecast')
          expect(find.textContaining('Previsto até'), findsOneWidget);
        if (const bool.fromEnvironment('CAPTURE_REVIEW')) {
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage();
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            final file = File('build/review/${entry.key}_$scenario.png');
            await file.parent.create(recursive: true);
            await file.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        if (entry.key == 'search') {
          await tester.tap(find.byTooltip('Filtros'));
          await tester.pumpAndSettle();
          expect(find.text('Filtrar lançamentos'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Aplicar'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        if (entry.key == 'rules') {
          await tester.tap(find.byTooltip('Nova regra'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Salvar'));
          await tester.pump();
          expect(
              find.text('Preencha a descrição e a categoria.'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text('Cancelar'));
          await tester.pumpAndSettle();
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
