// lib/screens/main_shell.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../l10n/app_localizations.dart';
import 'finance_home_screen.dart';
import 'expenses_v2_screen.dart';
import 'recurring_screen.dart';
import 'accounts_screen.dart';
import 'budget_screen.dart';
import 'more_screen.dart';
import '../utils/haptics.dart';
import 'analysis_screen.dart';
import 'agenda_screen.dart';
import 'transaction_search_screen.dart';
import 'settings_screen.dart';
import 'statement_import_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  AppProvider? _app;
  final Set<int> _visited = {0};
  Widget get _body {
    _visited.add(_index);
    return IndexedStack(index: _index, children: [
      for (var i = 0; i < _screens.length; i++)
        _visited.contains(i) ? _screens[i] : const SizedBox.shrink(),
    ]);
  }

  static const _screens = [
    FinanceHomeScreen(),
    ExpensesScreen(),
    RecurringScreen(),
    AccountsScreen(),
    BudgetScreen(),
    MoreScreen(),
    AnalysisScreen(),
    AgendaScreen(),
    TransactionSearchScreen(),
    SettingsScreen(),
    StatementImportScreen(),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final app = context.read<AppProvider>();
    if (_app != app) {
      _app?.tabIndexNotifier.removeListener(_onTabChange);
      _app = app;
      app.tabIndexNotifier.addListener(_onTabChange);
    }
    if (_index != app.tabIndexNotifier.value) {
      _index = app.tabIndexNotifier.value;
    }
  }

  @override
  void dispose() {
    _app?.tabIndexNotifier.removeListener(_onTabChange);
    super.dispose();
  }

  void _onTabChange() {
    final app = context.read<AppProvider>();
    if (_index != app.tabIndexNotifier.value && mounted) {
      setState(() {
        _index = app.tabIndexNotifier.value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (MediaQuery.sizeOf(context).width >= 900) {
      return Scaffold(
          body: Row(children: [
        SizedBox(
            width: 220,
            child: SafeArea(
                child: ListView(children: [
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nexo',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w800))),
              for (final entry in const [
                (0, 'Resumo', Icons.dashboard_outlined),
                (8, 'Transações', Icons.receipt_long_outlined),
                (3, 'Contas e cartões', Icons.account_balance_wallet_outlined),
                (2, 'Recorrentes', Icons.repeat),
                (4, 'Orçamentos e objetivos', Icons.pie_chart_outline),
                (6, 'Análises', Icons.bar_chart),
                (7, 'Agenda', Icons.event_note),
                (10, 'Importar', Icons.upload_file_outlined),
                (9, 'Configurações', Icons.settings_outlined),
                (5, 'Mais', Icons.more_horiz),
              ])
                ListTile(
                    selected: _index == entry.$1,
                    leading: Icon(entry.$3),
                    title: Text(entry.$2),
                    onTap: () => context
                        .read<AppProvider>()
                        .tabIndexNotifier
                        .value = entry.$1),
            ]))),
        const VerticalDivider(width: 1),
        Expanded(child: _body),
      ]));
    }
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        final app = context.read<AppProvider>();
        if (app.isTransactionSelectionMode) return;
        setState(() {
          _index = 0;
          app.tabIndexNotifier.value = 0;
        });
      },
      child: Scaffold(
        extendBody: false,
        body: _body,
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(40),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  height: 68,
                  indicatorShape: const CircleBorder(),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    return IconThemeData(
                      size: 24,
                      color: states.contains(WidgetState.selected)
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    );
                  }),
                ),
                child: NavigationBar(
                  labelBehavior:
                      NavigationDestinationLabelBehavior.onlyShowSelected,
                  selectedIndex: _index.clamp(0, 5),
                  animationDuration: const Duration(milliseconds: 120),
                  onDestinationSelected: (i) {
                    AppHaptics.tap(context, HapticStrength.selection);
                    final app = context.read<AppProvider>();
                    setState(() {
                      _index = i;
                      app.tabIndexNotifier.value = i;
                    });
                  },
                  destinations: [
                    const NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Início'),
                    const NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long),
                        label: 'Despesas'),
                    NavigationDestination(
                        icon: const Icon(Icons.repeat_rounded),
                        selectedIcon: const Icon(Icons.repeat_rounded),
                        label: l10n.main_recurring),
                    const NavigationDestination(
                        icon: Icon(Icons.account_balance_wallet_outlined),
                        selectedIcon: Icon(Icons.account_balance_wallet),
                        label: 'Contas'),
                    const NavigationDestination(
                        icon: Icon(Icons.pie_chart_outline_rounded),
                        selectedIcon: Icon(Icons.pie_chart_rounded),
                        label: 'Orçamento'),
                    NavigationDestination(
                        icon: const Icon(Icons.more_horiz_outlined),
                        selectedIcon: const Icon(Icons.more_horiz),
                        label: l10n.main_more),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FadeIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const FadeIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 250),
  });

  @override
  State<FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.forward();
  }

  @override
  void didUpdateWidget(FadeIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: IndexedStack(
        index: widget.index,
        children: widget.children,
      ),
    );
  }
}
