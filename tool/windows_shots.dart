// Native screenshot target: the real shell, drawn by the real Windows engine,
// with fictitious data only. `flutter test` does not use the Windows font
// stack, so typography has to be judged here. Never package this entrypoint.
//
//   flutter build windows --release --target tool/windows_shots.dart
//   Nexo.exe --test-profile=shots --tab=0            (0 Hoje, 11 Investir)
//   Nexo.exe --test-profile=shots --specimen --fonts=<folder of .ttf>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'package:nexo/database/db_helper.dart';
import 'package:nexo/investments/cdi_benchmark.dart';
import 'package:nexo/l10n/app_localizations.dart';
import 'package:nexo/screens/main_shell.dart';
import 'package:nexo/services/desktop_profile.dart';
import 'package:nexo/theme/app_theme.dart';

import 'demo_data.dart';

class _Offline extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('Offline capture');
}

String? _arg(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}

/// The same lines in each family, so that the engine's own rendering can be
/// compared side by side at real pixel sizes.
class _Specimen extends StatelessWidget {
  const _Specimen(this.families);
  final List<String> families;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.black,
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Wrap(spacing: 28, runSpacing: 20, children: [
            for (final family in families)
              SizedBox(
                  width: 440,
                  child: DefaultTextStyle(
                      style: TextStyle(
                          fontFamily: family, color: const Color(0xFFE6E8EC)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(family,
                                style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                    color: Color(0xFF7DD3FC))),
                            const SizedBox(height: 6),
                            for (final s in const <double>[
                              10,
                              11,
                              12,
                              13,
                              14,
                              16
                            ])
                              Text(
                                  '$s  Patrimônio líquido: rentabilidade R\$ 12.480,57',
                                  style: TextStyle(fontSize: s)),
                            const SizedBox(height: 6),
                            for (final w in const [
                              FontWeight.w400,
                              FontWeight.w500,
                              FontWeight.w600,
                              FontWeight.w700,
                              FontWeight.w800,
                              FontWeight.w900
                            ])
                              Text('${w.value}  Investir hoje R\$ 1.234,56',
                                  style:
                                      TextStyle(fontSize: 18, fontWeight: w)),
                            const SizedBox(height: 6),
                            for (final w in const [
                              FontWeight.w600,
                              FontWeight.w700,
                              FontWeight.w900
                            ])
                              Text('R\$ 18.250,32',
                                  style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: w,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ])),
                          ])))
          ])
        ]));
  }
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows || !args.any((a) => a.startsWith('--test-profile'))) {
    exit(64);
  }
  HttpOverrides.global = _Offline();
  await DesktopProfile.initialize(args);
  await initializeDateFormatting('pt_BR');

  if (args.contains('--specimen')) {
    final families = <String>['Segoe UI', 'Segoe UI Variable'];
    final folder = _arg(args, 'fonts');
    if (folder != null) {
      final groups = <String, List<File>>{};
      for (final f in Directory(folder).listSync().whereType<File>()) {
        final name = f.uri.pathSegments.last;
        if (!name.endsWith('.ttf')) continue;
        groups.putIfAbsent(name.split('-').first, () => []).add(f);
      }
      for (final e in groups.entries) {
        final loader = FontLoader(e.key);
        for (final f in e.value) {
          loader.addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
        }
        await loader.load();
        families.add(e.key);
      }
    }
    runApp(MaterialApp(
        debugShowCheckedModeBanner: false, home: _Specimen(families)));
    return;
  }

  CdiSource.instance = () => CdiSource(
      clientFactory: () => MockClient((_) async => http.Response(
          '[{"data":"01/10/2026","valor":"0.05"},{"data":"02/10/2026","valor":"0.05"}]',
          200)));
  await DBHelper.database;
  await seedDemoInvestments();
  final app = demoApp();
  app.tabIndexNotifier.value = int.parse(_arg(args, 'tab') ?? '0');
  final dark = _arg(args, 'theme') != 'light';
  runApp(ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(seed: 'nexo', dark: dark),
          home: const MainShell())));
}
