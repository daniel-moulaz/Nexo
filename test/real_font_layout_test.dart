// Layouts measured with the font the app really ships. The other widget tests
// use the test font and a default theme, where a text that no longer fits
// cannot be seen: 12 px minimums and Inter's width only show up here.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nexo/database/db_helper.dart';
import 'package:nexo/investments/cdi_benchmark.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/screens/main_shell.dart';
import 'package:nexo/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../tool/demo_data.dart';

const _tabs = {
  0: 'Hoje',
  8: 'Extrato',
  4: 'Orçamento',
  3: 'Contas',
  11: 'Investir',
  2: 'Recorrentes',
  6: 'Análises',
  7: 'Agenda',
  9: 'Configurações',
  5: 'Mais',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        (await Directory.systemTemp.createTemp('nexo-font-')).path);
    await initializeDateFormatting('pt_BR');
    CdiSource.instance = () => CdiSource(
        clientFactory: () => MockClient((_) async => http.Response('[]', 200)));
    final loader = FontLoader(kBundledFont);
    for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      loader.addFont(File('assets/fonts/Inter/Inter-$weight.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    }
    await loader.load();
    final roboto = FontLoader('Roboto');
    for (final weight in const ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      roboto.addFont(File('assets/fonts/Inter/Inter-$weight.ttf')
          .readAsBytes()
          .then((b) => ByteData.view(b.buffer)));
    }
    await roboto.load();
    await DBHelper.database;
    await seedDemoInvestments();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('home_widget'), (call) async => true);
  });
  tearDownAll(DBHelper.close);

  // The logical window of a 1920x1080 monitor at 100, 125 and 150%, the
  // desktop minimum, and two phones.
  for (final size in const [
    Size(1920, 1009),
    Size(1536, 793),
    Size(1280, 649),
    Size(900, 600),
    Size(412, 915),
    Size(360, 640),
  ]) {
    for (final (scale, text) in const [(1.0, 1.0), (1000.0, 1.0), (1.0, 1.6)]) {
      testWidgets(
          '${size.width.toInt()}x${size.height.toInt()} amounts x$scale text x$text',
          (tester) async {
        debugDefaultTargetPlatformOverride =
            size.width >= 900 ? TargetPlatform.windows : TargetPlatform.android;
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        final app = demoApp(scale: scale);
        final problems = <String>[];
        var tab = 'Hoje';
        final previous = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.exception is MissingPluginException) return;
          final first = details.exceptionAsString().split('\n').first;
          problems.add('$tab: $first');
        };
        await tester.pumpWidget(ChangeNotifierProvider.value(
            value: app,
            child: MaterialApp(
                locale: const Locale('pt'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildTheme(seed: 'sky', dark: true, amoled: true),
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(text)),
                    child: child!),
                home: const MainShell())));
        for (final entry in _tabs.entries) {
          tab = entry.value;
          app.tabIndexNotifier.value = entry.key;
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 30)));
            await tester.pump(const Duration(milliseconds: 100));
          }
        }
        await tester.pumpWidget(const SizedBox());
        FlutterError.onError = previous;
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        expect(problems.toSet().toList(), isEmpty);
      });
    }
  }
}
