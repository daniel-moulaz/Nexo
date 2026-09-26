// lib/main.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'providers/app_provider.dart';
import 'services/budget_notification_service.dart';
import 'services/daily_reminder_service.dart';
import 'l10n/app_localizations.dart';
import 'theme/app_theme.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'screens/add_transaction_screen.dart';
import 'services/notification_service.dart';
import 'services/lended_notification_service.dart';
import 'services/quick_add_service.dart';
import 'services/loan_reminder_service.dart';
import 'services/credit_reminder_service.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

// TEMPORARY DIAGNOSTIC: keep true only long enough to confirm that Flutter can
// render a basic MaterialApp after all startup services and provider.load().
const bool _diagnosticRoot = true;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService().initialize();
  await LendedNotificationService().initialize();
  await BudgetNotificationService().initialize();
  await DailyReminderService().initialize();
  await LoanReminderService().initialize();
  await CreditReminderService().initialize();

  final provider = AppProvider();
  await provider.load();

  if (_diagnosticRoot) {
    runApp(const _DiagnosticApp());
    return;
  }

  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const ExpensyApp(),
    ),
  );
}

class _DiagnosticApp extends StatelessWidget {
  const _DiagnosticApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4)),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 72),
                  SizedBox(height: 20),
                  Text(
                    'APP OK',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Flutter está renderizando normalmente.\nTeste temporário de diagnóstico.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ExpensyApp extends StatefulWidget {
  const ExpensyApp({super.key});

  @override
  State<ExpensyApp> createState() => _ExpensyAppState();
}

class _ExpensyAppState extends State<ExpensyApp> {
  StreamSubscription<String?>? _quickAddSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialRoute = await QuickAddService.instance.getInitialRoute();
      if (initialRoute == QuickAddService.routeQuickAdd) {
        _pushQuickAdd();
      }
    });

    _quickAddSub = QuickAddService.instance.routeStream.listen((route) {
      if (route == QuickAddService.routeQuickAdd) {
        _pushQuickAdd();
      }
    });
  }

  void _pushQuickAdd() {
    final app = context.read<AppProvider>();
    if (!app.settings.onboarded) return;

    rootNavigatorKey.currentState?.push(
      ExpensySlideUpRoute(builder: (_) => const AddTransactionScreen()),
    );
  }

  @override
  void dispose() {
    _quickAddSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settingsRecord = context.select<AppProvider,
        (bool, String, String, String, String, bool, bool)>((app) {
      final s = app.settings;
      return (
        s.dynamicColorEnabled,
        s.languageCode,
        s.themeMode,
        s.themeSeed,
        s.appFont,
        s.amoledSurfaces,
        s.onboarded
      );
    });

    final usesDynamic = settingsRecord.$1;
    final languageCode = settingsRecord.$2;
    final themeMode = settingsRecord.$3;
    final themeSeed = settingsRecord.$4;
    final appFont = settingsRecord.$5;
    final amoledSurfaces = settingsRecord.$6;
    final onboarded = settingsRecord.$7;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final view = View.of(context);
        final mediaQueryData =
            MediaQueryData.fromView(view).copyWith(accessibleNavigation: false);

        return MediaQuery(
          data: mediaQueryData,
          child: MaterialApp(
            title: 'Expensy',
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: languageCode == 'system' ? null : Locale(languageCode),
            themeMode: resolveThemeMode(themeMode),
            theme: buildTheme(
              seed: themeSeed,
              dark: false,
              appFont: appFont,
              dynamicScheme: usesDynamic ? lightDynamic : null,
            ),
            darkTheme: buildTheme(
              seed: themeSeed,
              dark: true,
              amoled: amoledSurfaces,
              appFont: appFont,
              dynamicScheme: usesDynamic ? darkDynamic : null,
            ),
            home: onboarded ? const MainShell() : const OnboardingScreen(),
          ),
        );
      },
    );
  }
}
