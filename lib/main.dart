// lib/main.dart
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
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
import 'screens/notification_inbox_screen.dart';
import 'services/notification_service.dart';
import 'services/lended_notification_service.dart';
import 'services/quick_add_service.dart';
import 'services/loan_reminder_service.dart';
import 'services/credit_reminder_service.dart';
import 'services/finance_bootstrap_service.dart';
import 'services/nexo_security.dart';
import 'services/financial_reminders.dart';
import 'widgets/security_gate.dart';
import 'services/desktop_profile.dart';
import 'screens/financial_checkup_screen.dart';
import 'sync/supabase_auth.dart';
import 'sync/sync_config.dart';
import 'sync/sync_controller.dart';
import 'services/pluggy_inbox.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

void main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await DesktopProfile.initialize(arguments);
    await startNexo();
  } catch (_) {
    runApp(MaterialApp(
        home: Scaffold(
            body: Center(
                child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.folder_off_outlined, size: 48),
        const Text('Não foi possível abrir o Nexo.'),
        const Text(
            'Confira espaço e permissão na pasta de dados. Nenhum banco foi apagado. Feche outras janelas do Nexo e tente novamente.',
            textAlign: TextAlign.center),
        FilledButton(
            onPressed: () => main(arguments),
            child: const Text('Tentar novamente')),
      ]),
    )))));
  }
}

Future<void> startNexo() async {
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await NotificationService().initialize();
  await LendedNotificationService().initialize();
  await BudgetNotificationService().initialize();
  await DailyReminderService().initialize();
  await LoanReminderService().initialize();
  await CreditReminderService().initialize();

  final provider = AppProvider();
  await NexoSecurity.instance.load();
  await provider.load();
  await FinanceBootstrapService.apply(provider);
  final syncConfig = SyncConfig.current;
  SupabaseAuth.app = syncConfig == null ? null : SupabaseAuth(syncConfig);
  SyncController.instance = SyncController.forApp(
      syncConfig, SupabaseAuth.app, provider.reloadFromStorage,
      real: !DesktopProfile.isTest);
  // Open Finance reads real bank data: never in a Windows test profile.
  if (syncConfig != null && !DesktopProfile.isTest) {
    PluggyInbox.instance =
        PluggyInbox(SupabasePluggyRemote(syncConfig, SupabaseAuth.app!));
  }
  // Never blocks opening the app: offline or signed out just waits.
  unawaited(SyncController.instance?.start());
  NexoSecurity.instance.addListener(provider.updateHomeWidgets);
  provider
      .addListener(() => FinancialReminders.instance.requestRefresh(provider));
  FinancialReminders.instance.requestRefresh(provider);

  runApp(
    ChangeNotifierProvider.value(
      value: provider,
      child: const ExpensyApp(),
    ),
  );
}

class ExpensyApp extends StatefulWidget {
  const ExpensyApp({super.key});

  @override
  State<ExpensyApp> createState() => _ExpensyAppState();
}

class _ExpensyAppState extends State<ExpensyApp> {
  StreamSubscription<String?>? _quickAddSub;
  StreamSubscription<String>? _reminderSub;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final initialRoute = await QuickAddService.instance.getInitialRoute();
      if (initialRoute == QuickAddService.routeQuickAdd) {
        _pushQuickAdd();
      } else if (initialRoute == 'notification_inbox') {
        _pushInbox();
      }
    });

    _reminderSub = FinancialReminders.instance.routes.listen((route) {
      if (route == weeklyReviewRoute) _pushWeeklyReview();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await FinancialReminders.instance.listenToTaps() ==
          weeklyReviewRoute) {
        _pushWeeklyReview();
      }
    });

    _quickAddSub = QuickAddService.instance.routeStream.listen((route) {
      if (route == QuickAddService.routeQuickAdd) {
        _pushQuickAdd();
      } else if (route == 'notification_inbox') {
        _pushInbox();
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

  /// The review is generated on screen from local data; the notification
  /// itself never carries amounts. The security gate still applies.
  void _pushWeeklyReview() {
    if (!mounted || !context.read<AppProvider>().settings.onboarded) return;
    rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const FinancialCheckupScreen()));
  }

  void _pushInbox() {
    if (!mounted || !context.read<AppProvider>().settings.onboarded) return;
    rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const NotificationInboxScreen()));
  }

  @override
  void dispose() {
    _quickAddSub?.cancel();
    _reminderSub?.cancel();
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
        final mediaQueryData = MediaQueryData.fromView(view);

        return MediaQuery(
          data: mediaQueryData,
          child: MaterialApp(
            title: 'Nexo',
            navigatorKey: rootNavigatorKey,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => DesktopProfile.isTest
                ? Banner(
                    message: DesktopProfile.testName.isEmpty
                        ? 'TESTE LOCAL'
                        : 'TESTE ${DesktopProfile.testName.toUpperCase()}',
                    location: BannerLocation.topEnd,
                    child: SecurityGate(child: child!))
                : SecurityGate(child: child!),
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
