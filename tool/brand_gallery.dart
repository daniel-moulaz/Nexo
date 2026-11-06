// ignore_for_file: invalid_use_of_visible_for_testing_member
// Before and after of the main screens, in both themes and both layouts, from
// the real widgets with fictitious data. Writes to build/review/brand/.
//
//   flutter test tool/brand_gallery.dart --dart-define=SEED=nexo
//
// flutter test does not use the Windows text engine: for type on Windows, use
// tool/windows_shots.dart. Never committed output.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/investments/cdi_benchmark.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/screens/add_transaction_screen.dart';
import 'package:nexo/screens/main_shell.dart';
import 'package:nexo/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'demo_data.dart';

const _seed = String.fromEnvironment('SEED', defaultValue: 'nexo');
const _out = String.fromEnvironment('OUT', defaultValue: 'build/review/brand');
const _tabs = {
  'hoje': 0,
  'extrato': 8,
  'orcamento': 4,
  'investir': 11,
  'mais': 5,
};

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(File(f).readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'Nexo',
        packageName: 'nexo',
        version: '0',
        buildNumber: '0',
        buildSignature: '');
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await databaseFactory.setDatabasesPath(
        (await Directory.systemTemp.createTemp('nexo-brand-')).path);
    await initializeDateFormatting('pt_BR');
    CdiSource.instance = () => CdiSource(
        clientFactory: () => MockClient((_) async => http.Response('[]', 200)));
    final inter = [
      for (final w in const ['Regular', 'Medium', 'SemiBold', 'Bold'])
        'assets/fonts/Inter/Inter-$w.ttf'
    ];
    await _font('Inter', inter);
    await _font('Roboto', inter);
    await _font('MaterialIcons',
        ['${artifacts.path}/material_fonts/MaterialIcons-Regular.otf']);
    await DBHelper.database;
    await seedDemoInvestments();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
    await Directory(_out).create(recursive: true);
  });
  tearDownAll(DBHelper.close);

  for (final desktop in [false, true]) {
    for (final dark in [true, false]) {
      for (final screen in [..._tabs.keys, 'lancar']) {
        final name =
            '$screen-${desktop ? 'windows' : 'celular'}-${dark ? 'escuro' : 'claro'}';
        testWidgets(name, (tester) async {
          debugDefaultTargetPlatformOverride =
              desktop ? TargetPlatform.windows : TargetPlatform.android;
          final size = desktop ? const Size(1440, 900) : const Size(412, 915);
          final ratio = desktop ? 1.0 : 2.0;
          tester.view.physicalSize = size * ratio;
          tester.view.devicePixelRatio = ratio;
          final app = demoApp();
          app.settings.themeMode = dark ? 'dark' : 'light';
          if (screen != 'lancar') app.tabIndexNotifier.value = _tabs[screen]!;
          final boundary = GlobalKey();
          await tester.pumpWidget(ChangeNotifierProvider.value(
              value: app,
              child: RepaintBoundary(
                  key: boundary,
                  child: MaterialApp(
                      debugShowCheckedModeBanner: false,
                      locale: const Locale('pt'),
                      localizationsDelegates:
                          AppLocalizations.localizationsDelegates,
                      supportedLocales: AppLocalizations.supportedLocales,
                      theme: buildTheme(
                          seed: _seed,
                          dark: dark,
                          amoled: dark && _seed != 'nexo'),
                      home: screen == 'lancar'
                          ? const AddTransactionScreen()
                          : const MainShell()))));
          for (var i = 0; i < 16; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 40)));
            await tester.pump(const Duration(milliseconds: 120));
          }
          await tester.runAsync(() async {
            final image = await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: ratio);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$_out/$name.png')
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
  }
}
