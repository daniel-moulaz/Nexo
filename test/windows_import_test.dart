import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:expensy/database/database_platform.dart';
import 'package:expensy/database/db_helper.dart';
import 'package:expensy/models/models.dart';
import 'package:expensy/providers/app_provider.dart';
import 'package:expensy/screens/statement_import_screen.dart';

class _Picker extends FilePicker {
  FilePickerResult? result;
  @override
  Future<FilePickerResult?> pickFiles(
          {String? dialogTitle,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Function(FilePickerStatus)? onFileLoading,
          bool allowCompression = true,
          int compressionQuality = 30,
          bool allowMultiple = false,
          bool withData = false,
          bool withReadStream = false,
          bool lockParentWindow = false,
          bool readSequential = false}) async =>
      result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late AppProvider app;
  late _Picker picker;
  setUpAll(() => initializeDateFormatting('pt_BR'));
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('nexo-import-qa-');
    await DatabasePlatform.initialize(testDirectory: directory.path);
    app = AppProvider();
    app.settings.currency = 'BRL';
    app.settings.budgetAlertsEnabled = false;
    app.categories = await DBHelper.getCategories();
    await app.addAccount(Account(
        id: 'bank',
        name: 'Banco Teste',
        type: 'bank',
        balance: 1000,
        currency: 'BRL',
        colorValue: 0));
    picker = _Picker();
    FilePicker.platform = picker;
  });
  tearDown(() async {
    await DBHelper.close();
    app.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    });
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: app, child: const MaterialApp(home: StatementImportScreen())));
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, String name, String content) async {
    final file = File('${directory.path}/$name');
    await tester.runAsync(() => file.writeAsString(content));
    picker.result = FilePickerResult(
        [PlatformFile(name: name, size: content.length, path: file.path)]);
    await tester.ensureVisible(
        find.widgetWithIcon(OutlinedButton, Icons.upload_file_rounded));
    await tap(
        tester, find.widgetWithIcon(OutlinedButton, Icons.upload_file_rounded));
    await settle(tester);
  }

  for (final format in ['csv', 'txt', 'ofx']) {
    testWidgets(
        '$format preview, explicit import and duplicate review preserve balance',
        (tester) async {
      await open(tester);
      final content = format == 'ofx'
          ? '<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST><STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20260930120000<TRNAMT>-32.90<FITID>synthetic-1<NAME>Mercado Teste</STMTTRN></BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>'
          : 'Data;Descrição;Valor\n30/09/2026;Mercado Teste;-32,90\n';
      await choose(tester, 'sintetico.$format', content);
      expect(find.textContaining('1 lançamentos prontos'), findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join(' | '));
      expect(app.transactions, isEmpty);
      expect(app.accountById('bank')!.balance, 1000);
      await tester.ensureVisible(find.text('Importar selecionados'));
      await tap(tester, find.text('Importar selecionados'));
      await settle(tester);
      expect(app.transactions.single.amount, 32.9);
      expect(app.accountById('bank')!.balance, 1000);
      await choose(tester, 'sintetico.$format', content);
      await tester.ensureVisible(find.text('Importar selecionados'));
      await tap(tester, find.text('Importar selecionados'));
      await settle(tester);
      expect(find.text('Pode ser o mesmo lançamento'), findsOneWidget);
      await tap(tester, find.text('Ignorar esta linha'));
      await settle(tester);
      expect(app.transactions, hasLength(1));
      expect(app.accountById('bank')!.balance, 1000);
      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  }
  testWidgets(
      'Picker cancellation, missing file and malformed CSV are harmless',
      (tester) async {
    await open(tester);
    await tester.ensureVisible(
        find.widgetWithIcon(OutlinedButton, Icons.upload_file_rounded));
    await tap(
        tester, find.widgetWithIcon(OutlinedButton, Icons.upload_file_rounded));
    await settle(tester);
    expect(app.transactions, isEmpty);
    picker.result = FilePickerResult([
      PlatformFile(
          name: 'missing.csv', size: 1, path: '${directory.path}/missing.csv')
    ]);
    await tester.ensureVisible(
        find.widgetWithIcon(OutlinedButton, Icons.upload_file_rounded));
    await tap(
        tester, find.widgetWithIcon(OutlinedButton, Icons.upload_file_rounded));
    await settle(tester);
    expect(
        find.textContaining('Não foi possível ler o arquivo.'), findsOneWidget);
    await choose(tester, 'invalid.csv', 'not,a,statement\ninvalid,data,here');
    expect(find.textContaining('Não encontrei lançamentos'), findsOneWidget);
    expect(app.transactions, isEmpty);
    expect(app.accountById('bank')!.balance, 1000);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
