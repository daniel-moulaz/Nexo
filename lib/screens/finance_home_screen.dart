import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/cash_forecast.dart';
import '../services/cash_timeline.dart';
import '../services/card_commitment.dart';
import '../services/current_invoice_summary.dart';
import '../services/financial_analysis.dart';
import '../services/finance_rules.dart';
import '../services/platform_capabilities.dart';
import '../services/transaction_metadata_service.dart';
import '../services/week_summary.dart';
import '../services/spendable.dart';
import '../services/charge_alerts.dart';
import '../services/cancel_intents.dart';
import '../services/bank_snapshots.dart';
import '../services/balance_check.dart';
import '../services/liquidity.dart';
import 'due_plan_screen.dart';
import '../utils/finance_input.dart';
import '../widgets/analysis_widgets.dart';
import '../widgets/cash_timeline_chart.dart';
import '../widgets/nexo_ui.dart';
import '../widgets/shared_widgets.dart' show CategoryDot;
import 'accounts_screen.dart';
import 'analysis_screen.dart';
import 'add_transaction_screen.dart';
import 'agenda_screen.dart';
import 'budget_screen.dart';
import 'card_invoice_screen.dart';
import 'debt_overview_screen.dart';
import 'financial_checkup_screen.dart';
import 'notification_inbox_screen.dart';
import 'recurring_detail_screen.dart';
import 'recurring_screen.dart';
import 'transaction_search_screen.dart';
import 'transfer_screen.dart';
import 'statement_import_screen.dart';
import 'month_review_screen.dart';
import 'net_worth_screen.dart';

class FinanceHomeScreen extends StatefulWidget {
  const FinanceHomeScreen({super.key});
  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen>
    with WidgetsBindingObserver {
  Future<List<Map<String, dynamic>>>? _payments;
  List<AppTransaction>? _lastTransactions;
  DateTime? _month;
  int _horizon = 30;
  Set<String> _dismissedSubscriptions = {};
  Set<String> _dismissedAlerts = {};
  Map<String, int> _cancelIntents = {};
  List<BankAccountSnapshot> _bank = const [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDismissed();
  }

  Future<void> _loadDismissed() async {
    try {
      final alerts = await CancelIntents.dismissedAlerts();
      final intents = await CancelIntents.load();
      if (mounted) {
        setState(() {
          _dismissedAlerts = alerts;
          _cancelIntents = intents;
        });
      }
      final v = await loadDismissedSubscriptions();
      if (mounted) setState(() => _dismissedSubscriptions = v);
      final bank = await BankSnapshots.load();
      if (mounted) setState(() => _bank = bank);
    } catch (_) {
      // Preferences unavailable: suggestions still show, nothing breaks.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final txs = context.watch<AppProvider>().transactions;
    if (!identical(_lastTransactions, txs)) {
      _lastTransactions = txs;
      _payments = _readPayments();
    }
  }

  Future<List<Map<String, dynamic>>> _readPayments() async =>
      (await DBHelper.database).query('card_invoice_payments');
  Future<void> _refresh() async {
    final future = _readPayments();
    setState(() => _payments = future);
    try {
      await future;
    } catch (_) {/* FutureBuilder offers retry. */}
  }

  Future<void> _open(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) {
      await _loadDismissed();
      await _refresh();
    }
  }

  void _event(AppProvider app, ForecastEvent event) {
    if (event.kind == 'invoice') {
      _open(
          CardInvoiceScreen(cardId: event.id, initialCycleEnd: event.cycleEnd));
    } else if (event.kind == 'recurring') {
      final r = app.recurring.where((r) => r.id == event.id).firstOrNull;
      if (r != null) {
        _open(RecurringDetailScreen(
            recurring: r,
            fmt: (v) =>
                analysisMoney(app, app.convertToMain(v, event.currency))));
      } else {
        _open(const AgendaScreen());
      }
    } else {
      final t = app.transactions.where((t) => t.id == event.id).firstOrNull;
      if (t != null) {
        _open(AddTransactionScreen(existing: t, initialType: t.type));
      } else {
        _open(const AgendaScreen());
      }
    }
  }

  void _explain() => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (ctx) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Como ler seu painel',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                const Text(
                    'Saldo em contas\nDinheiro nas contas incluídas no total, sem cartões e ouro.\n\nApós cartões\nSaldo em contas menos toda a dívida restante dos cartões incluídos, inclusive parcelas futuras já lançadas. Não é um limite seguro para novas compras.\n\nGastou no mês\nConsumo realizado, incluindo compras no cartão. Transferências, reservas e pagamentos de fatura não contam de novo. Pendências e reembolsos aparecem separados.\n\nPrevisão\nSaldo atual mais entradas e saídas cadastradas, incluindo atrasados. Não presume salário nem gastos variáveis futuros. Contratos de empréstimo e dinheiro emprestado entre pessoas não entram automaticamente: consulte Dívidas.\n\nMeses anteriores\nA troca de mês altera receitas, despesas e categorias. Saldos, cartões, orçamentos atuais e previsão continuam mostrando a situação de hoje.'),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Entendi')),
              ])));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final month = _month ?? DateTime(now.year, now.month);
    final currentMonth = month.year == now.year && month.month == now.month;
    final filter = FinancialAnalysis.month(month, now);
    final data = analyzePeriod(app, filter);
    final previous = analyzePeriod(
        app, FinancialAnalysis.previousMonth(filter, partial: currentMonth));
    final commitment =
        CardCommitment.calculate(app.accounts, app.convertToMain);
    String money(double value) => analysisMoney(app, value);

    return Scaffold(
      appBar: AppBar(
          toolbarHeight: math.max(
              kToolbarHeight, 42 * MediaQuery.textScalerOf(context).scale(1)),
          automaticallyImplyLeading: false,
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_greeting(app.settings.userName),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(_todayLabel(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            IconButton(
                tooltip: 'Buscar lançamentos',
                onPressed: () => _open(const TransactionSearchScreen()),
                icon: const Icon(Icons.search)),
            IconButton(
                tooltip: app.settings.hideBalance
                    ? 'Mostrar valores'
                    : 'Ocultar valores',
                onPressed: () =>
                    app.updateSetting('hideBalance', !app.settings.hideBalance),
                icon: Icon(app.settings.hideBalance
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined)),
            IconButton(
                tooltip: PlatformCapabilities.bankNotifications
                    ? 'Revisar compras detectadas'
                    : 'Importar extrato',
                onPressed: () => _open(PlatformCapabilities.bankNotifications
                    ? const NotificationInboxScreen()
                    : const StatementImportScreen()),
                icon: Icon(PlatformCapabilities.bankNotifications
                    ? Icons.inbox_outlined
                    : Icons.upload_file_outlined)),
          ]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _payments,
          builder: (context, snapshot) {
            CashForecast at(DateTime end) => CashForecast.calculate(
                now: today,
                until: end,
                accounts: app.accounts,
                transactions: app.transactions,
                recurring: app.recurring,
                metadata: app.transactionMetadata,
                invoicePayments: snapshot.data!,
                convert: app.convertToMain);
            final forecast = snapshot.hasData
                ? at(DateTime(today.year, today.month, today.day + _horizon))
                : null;
            final monthEnd = snapshot.hasData
                ? at(DateTime(today.year, today.month + 1, 0))
                : null;
            final timeline = forecast == null
                ? null
                : CashTimeline.build(forecast,
                    now: today, days: _horizon, convert: app.convertToMain);
            final overdue =
                timeline?.overdue.where((e) => e.amount < 0).toList() ??
                    <ForecastEvent>[];
            final budgets = app.budgets.toList()
              ..sort((a, b) =>
                  app.budgetProgressRaw(b).compareTo(app.budgetProgressRaw(a)));

            final hidden = app.settings.hideBalance;
            // Month in view: one control on top, as in the period selectors
            // of the reference apps; the cards below follow it.
            final monthBar = Row(children: [
              Expanded(
                  child: Text(currentMonth ? 'Mês atual' : 'Mês escolhido',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: cs.onSurfaceVariant))),
              Flexible(
                  child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Material(
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                                color:
                                    cs.outlineVariant.withValues(alpha: .6))),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: 'Mês anterior',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => setState(() => _month =
                                  DateTime(month.year, month.month - 1)),
                              icon: const Icon(Icons.chevron_left, size: 20)),
                          Text(ptMonthYear(month),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          IconButton(
                              tooltip: 'Próximo mês',
                              visualDensity: VisualDensity.compact,
                              onPressed: currentMonth
                                  ? null
                                  : () => setState(() => _month =
                                      DateTime(month.year, month.month + 1)),
                              icon: const Icon(Icons.chevron_right, size: 20)),
                        ]),
                      ))),
            ]);
            final result = data.income - data.expense;
            final kpis = Column(children: [
              Row(children: [
                Expanded(
                    child: _Kpi(
                        label: 'Saldo em contas',
                        value: money(commitment.cash),
                        hint: 'hoje',
                        big: true,
                        onInfo: _explain,
                        onTap: () => _open(const AccountsScreen()))),
                const SizedBox(width: 10),
                Expanded(
                    child: _Kpi(
                        label: 'Resultado',
                        value: money(result),
                        hint: currentMonth ? 'até hoje' : 'no mês',
                        big: true,
                        color: hidden
                            ? null
                            : result >= 0
                                ? NexoTones.income(context)
                                : NexoTones.expense(context),
                        onTap: () =>
                            _open(AnalysisScreen(initialMonth: month)))),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                    child: _Kpi(
                        label: 'Receitas',
                        value: money(data.income),
                        color: hidden ? null : NexoTones.income(context),
                        onTap: () =>
                            _open(AnalysisScreen(initialMonth: month)))),
                const SizedBox(width: 10),
                Expanded(
                    child: _Kpi(
                        label: 'Despesas',
                        value: money(data.expense),
                        color: hidden ? null : NexoTones.expense(context),
                        onTap: () =>
                            _open(AnalysisScreen(initialMonth: month)))),
              ]),
              const SizedBox(height: 10),
              NexoCard(
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  Expanded(
                      child: NexoStatPill(
                          label: 'Cartões',
                          value: money(commitment.outstanding),
                          onTap: () => _open(const DebtOverviewScreen()))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: NexoStatPill(
                          label: 'Após cartões',
                          value: money(commitment.available),
                          onTap: _explain)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: NexoStatPill(
                          label: 'Previsão',
                          value: monthEnd == null
                              ? '—'
                              : money(monthEnd.projected),
                          onTap: () =>
                              _open(const AgendaScreen(initialDays: -1)))),
                ]),
              ),
            ]);
            // "Saídas por dia": the month as a calendar, like the reference
            // apps, with the three numbers that summarize it.
            final daysWithSpending =
                data.dailyExpense.values.where((v) => v > 0).length;
            final daysElapsed = currentMonth
                ? today.day
                : DateTime(month.year, month.month + 1, 0).day;
            final biggestDay = data.dailyExpense.entries.isEmpty
                ? null
                : data.dailyExpense.entries
                    .reduce((a, b) => b.value > a.value ? b : a);
            final dailyCard = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  NexoSectionTitle('Saídas por dia',
                      subtitle:
                          '${ptMonthYear(month)} · quanto saiu em cada dia'),
                  const SizedBox(height: 6),
                  Text.rich(TextSpan(children: [
                    TextSpan(
                        text: money(data.expense),
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            fontFeatures: NexoTones.figures)),
                    TextSpan(
                        text: '  em $daysWithSpending dia(s) com saída',
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
                  const SizedBox(height: 10),
                  if (hidden)
                    const Text('Calendário oculto no modo privado.')
                  else
                    NexoSpendingCalendar(
                        month: month,
                        daily: data.dailyExpense,
                        compact: (v) =>
                            NumberFormat.compact(locale: 'pt_BR').format(v),
                        onDay: (day) => openAnalysisEntries(
                            context,
                            data.realized.where((t) =>
                                t.type == 'expense' &&
                                DateTime(t.date.year, t.date.month,
                                        t.date.day) ==
                                    day),
                            'Gastos de ${DateFormat('d/MM', 'pt_BR').format(day)}')),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: NexoStatPill(
                            label: 'Média por dia',
                            value: money(daysElapsed == 0
                                ? 0
                                : data.expense / daysElapsed))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: NexoStatPill(
                            label: 'Maior dia',
                            value: biggestDay == null || biggestDay.value <= 0
                                ? '—'
                                : '${biggestDay.key.day} · ${money(biggestDay.value)}')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: NexoStatPill(
                            label: 'Dias sem saída',
                            value: '${daysElapsed - daysWithSpending}')),
                  ]),
                ]));

            final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
            final previousMonth = DateTime(month.year, month.month - 1);
            final previousFull =
                analyzePeriod(app, FinancialAnalysis.month(previousMonth, now));
            List<double> cumulative(FinancialAnalysis a, DateTime m, int days) {
              var sum = 0.0;
              return [
                for (var d = 1; d <= days; d++)
                  sum += a.dailyVariable[DateTime(m.year, m.month, d)] ?? 0
              ];
            }

            final paceNow =
                cumulative(data, month, currentMonth ? today.day : daysInMonth);
            final pacePrevious = cumulative(previousFull, previousMonth,
                DateTime(month.year, month.month, 0).day);
            final paceThen = pacePrevious.isEmpty
                ? 0.0
                : pacePrevious[
                    math.min(paceNow.length, pacePrevious.length) - 1];

            final budgetFree = spendable(
                transactions: app.transactions,
                metadata: app.transactionMetadata,
                recurring: app.recurring,
                goals: app.savingsGoals,
                toMain: (t) => app.convertToMain(
                    t.amount,
                    t.currency.isEmpty
                        ? app.accountById(t.accountId)?.currency ??
                            app.settings.currency
                        : t.currency),
                convert: app.convertToMain,
                currencyOf: (r) =>
                    app.accountById(r.accountId)?.currency ??
                    app.settings.currency,
                now: now);
            // What fixed income leaves for variable spending this month.
            final variableAllowance = budgetFree.fixedIncome -
                budgetFree.fixedBills -
                budgetFree.pendingBills -
                budgetFree.goals;
            final ideal =
                currentMonth && budgetFree.hasBase && variableAllowance > 0
                    ? variableAllowance
                    : null;
            final monthCard = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  NexoSectionTitle('Resumo de ${ptMonthYear(month)}',
                      subtitle: currentMonth ? 'Até hoje' : 'Mês completo'),
                  const SizedBox(height: 6),
                  LayoutBuilder(builder: (context, c) {
                    final flows = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Value(
                              label: 'Entrou',
                              value: money(data.income),
                              detail: data.extraIncome > .005 &&
                                      data.fixedIncome > .005
                                  ? '${money(data.fixedIncome)} fixa · ${money(data.extraIncome)} extra'
                                  : null,
                              icon: Icons.south_west,
                              color: NexoTones.income(context),
                              onTap: () => openAnalysisEntries(
                                  context,
                                  data.realized.where((t) =>
                                      t.type == 'income' &&
                                      !FinancialAnalysis.isRefund(
                                          t,
                                          app.transactionMetadata[t.id] ??
                                              TransactionMetadata(
                                                  transactionId: t.id))),
                                  'Receitas · ${ptMonthYear(month)}')),
                          const SizedBox(height: 8),
                          _Value(
                              label: 'Gastou',
                              value: money(data.expense),
                              icon: Icons.north_east,
                              color: NexoTones.expense(context),
                              onTap: () => openAnalysisEntries(
                                  context,
                                  data.realized
                                      .where((t) => t.type == 'expense'),
                                  'Despesas · ${ptMonthYear(month)}')),
                        ]);
                    if (hidden) return flows;
                    final gauge = NexoSavingsGauge(
                        ratio:
                            data.income > 0 ? data.result / data.income : null,
                        label: 'do que entrou\nficou com você');
                    if (c.maxWidth / MediaQuery.textScalerOf(context).scale(1) <
                        300) {
                      return Column(children: [flows, gauge]);
                    }
                    return Row(children: [
                      Expanded(child: flows),
                      const SizedBox(width: 12),
                      gauge
                    ]);
                  }),
                  if (!hidden &&
                      (paceNow.any((v) => v > 0) ||
                          pacePrevious.any((v) => v > 0))) ...[
                    const SizedBox(height: 14),
                    Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Ritmo de gastos variáveis',
                              style: Theme.of(context).textTheme.titleSmall),
                          _Legend(color: cs.primary, label: 'Este mês'),
                          if (ideal != null)
                            _Legend(
                                color: cs.tertiary,
                                label: 'Ritmo ideal',
                                dashed: true),
                          if (pacePrevious.any((v) => v > 0))
                            _Legend(
                                color: cs.outline,
                                label: 'Mês anterior',
                                dashed: true),
                        ]),
                    const SizedBox(height: 8),
                    NexoSpendingPace(
                        current: paceNow,
                        previous: pacePrevious,
                        money: money,
                        ideal: ideal,
                        monthDays: daysInMonth),
                    if (ideal != null && paceNow.isNotEmpty)
                      Builder(builder: (context) {
                        final expected = ideal * paceNow.length / daysInMonth;
                        final gap = paceNow.last - expected;
                        return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                gap.abs() < 1
                                    ? 'No ritmo ideal para fechar o mês dentro da renda fixa.'
                                    : gap > 0
                                        ? '${money(gap)} acima do ritmo ideal para o dia ${paceNow.length}.'
                                        : '${money(-gap)} abaixo do ritmo ideal: sobra espaço.',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: gap > 0
                                        ? NexoTones.expense(context)
                                        : NexoTones.income(context))));
                      }),
                  ],
                  if (!hidden)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            _changeText(
                                data,
                                previous,
                                currentMonth
                                    ? 'até o dia ${today.day}'
                                    : 'no mês'),
                            style: Theme.of(context).textTheme.bodySmall)),
                  if (data.pendingExpense > 0 || data.refunds > 0)
                    Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                            [
                              if (data.pendingExpense > 0)
                                'Pendente: ${money(data.pendingExpense)}',
                              if (data.refunds > 0)
                                'Reembolsos: ${money(data.refunds)}',
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall)),
                  if (!currentMonth)
                    TextButton(
                        onPressed: () => setState(() => _month = null),
                        child: const Text('Voltar para este mês')),
                ]));

            final spendCard = _Panel(
                child: _SpendableBody(
                    s: budgetFree,
                    hidden: hidden,
                    money: money,
                    onSetup: () => _open(const RecurringScreen())));

            final quick = Row(children: [
              for (final action in <(String, IconData, Widget)>[
                (
                  'Despesa',
                  Icons.add,
                  const AddTransactionScreen(initialType: 'expense')
                ),
                (
                  'Receita',
                  Icons.south_west,
                  const AddTransactionScreen(initialType: 'income')
                ),
                ('Transferir', Icons.swap_horiz, const TransferScreen()),
                (
                  'Dívidas',
                  Icons.account_balance_outlined,
                  const DebtOverviewScreen()
                ),
                ('Recorrentes', Icons.event_repeat, const RecurringScreen()),
              ])
                Expanded(
                    child: NexoQuickAction(
                        label: action.$1,
                        icon: action.$2,
                        primary: action.$1 == 'Despesa',
                        onTap: () => _open(action.$3))),
            ]);

            final firstShortfall = timeline?.points
                .where((point) => point.balance < 0)
                .firstOrNull;
            final hot = budgets
                .where((b) => app.budgetProgressRaw(b) >= .8)
                .firstOrNull;
            final gap =
                timeline == null ? null : shortfalls(timeline).firstOrNull;
            final insights = <NexoInsight>[
              if (overdue.isNotEmpty)
                NexoInsight(
                    icon: Icons.notification_important_outlined,
                    color: NexoTones.expense(context),
                    title:
                        '${overdue.length} ${overdue.length == 1 ? 'vencimento em atraso' : 'vencimentos em atraso'}',
                    subtitle:
                        '${money(overdue.fold<double>(0, (s, e) => s - app.convertToMain(e.amount, e.currency)))} · revisar na agenda',
                    action: 'Ver',
                    onTap: () => _open(const AgendaScreen()))
              else if (gap != null && !hidden)
                NexoInsight(
                    icon: Icons.event_busy_outlined,
                    color: NexoTones.expense(context),
                    title:
                        'Faltam ${money(gap.missing)} para ${gap.event.title} de ${ptShortDate(gap.event.date)}',
                    subtitle:
                        'Veja o que chega a tempo: reservas, investimentos e pagamento parcial.',
                    action: 'Plano',
                    onTap: () => _open(DuePlanScreen(shortfall: gap)))
              else if (firstShortfall != null && !hidden)
                NexoInsight(
                    icon: Icons.event_busy_outlined,
                    color: NexoTones.expense(context),
                    title:
                        'Previsão abaixo de zero em ${ptShortDate(firstShortfall.date)}',
                    subtitle: 'Confira entradas e vencimentos na agenda.',
                    action: 'Ver',
                    onTap: () => _open(AgendaScreen(initialDays: _horizon))),
              if (currentMonth && data.pendingExpense > 0)
                NexoInsight(
                    icon: Icons.schedule,
                    color: NexoTones.warning(context),
                    title: 'Despesas pendentes neste mês',
                    subtitle: '${money(data.pendingExpense)} ainda a pagar',
                    action: 'Agenda',
                    onTap: () => _open(const AgendaScreen())),
              if (!hidden && hot != null)
                NexoInsight(
                    icon: Icons.pie_chart_outline,
                    color: app.budgetExceeded(hot)
                        ? NexoTones.expense(context)
                        : NexoTones.warning(context),
                    title:
                        'Orçamento de ${app.categoryById(hot.categoryId)?.name ?? 'categoria'} em ${(app.budgetProgressRaw(hot) * 100).round()}%',
                    subtitle: app.budgetExceeded(hot)
                        ? 'Passou ${money(app.budgetSpent(hot) - app.budgetLimit(hot))} do limite'
                        : 'Restam ${money(app.budgetRemaining(hot))}',
                    action: 'Ver',
                    onTap: () => _open(const BudgetScreen())),
              if (!hidden &&
                  currentMonth &&
                  paceThen > 0 &&
                  paceNow.isNotEmpty &&
                  paceNow.last > paceThen * 1.1)
                NexoInsight(
                    icon: Icons.speed,
                    color: NexoTones.warning(context),
                    title: 'Gastando mais rápido que no mês passado',
                    subtitle:
                        '${money(paceNow.last)} até hoje, contra ${money(paceThen)} no mesmo dia',
                    action: 'Ver',
                    onTap: () => _open(AnalysisScreen(initialMonth: month))),
            ];
            final subscriptions = hidden
                ? const []
                : detectSubscriptions(app, _dismissedSubscriptions);
            if (subscriptions.isNotEmpty) {
              insights.add(NexoInsight(
                  icon: Icons.auto_awesome_outlined,
                  color: cs.tertiary,
                  title:
                      '${subscriptions.length} ${subscriptions.length == 1 ? 'possível assinatura' : 'possíveis assinaturas'} sem cadastro',
                  subtitle:
                      '~${money(subscriptions.fold<double>(0, (s, c) => s + c.monthlyAmount))} por mês. Cadastre para prever e ser lembrado.',
                  action: 'Ver',
                  onTap: () => _open(const RecurringScreen())));
            }
            // Yesterday in one line, with what fits today (the daily digest).
            final yesterday = DateTime(today.year, today.month, today.day - 1);
            final yday = analyzePeriod(
                app, AnalysisFilter(from: yesterday, to: yesterday));
            if (yday.expense > 0 || yday.income > 0) {
              final onCard = yday.realized
                  .where((t) =>
                      t.type == 'expense' &&
                      app.accountById(t.accountId)?.type == 'credit')
                  .fold<double>(0, (s, t) => s + t.amount);
              insights.add(NexoInsight(
                  icon: Icons.history_toggle_off,
                  color: cs.primary,
                  title: hidden
                      ? 'Resumo de ontem'
                      : 'Ontem: saiu ${money(yday.expense)}${yday.income > 0 ? ', entrou ${money(yday.income)}' : ''}',
                  subtitle: hidden
                      ? 'Toque para ver os lançamentos.'
                      : [
                          if (onCard > 0) '${money(onCard)} no cartão',
                          if (budgetFree.hasBase && budgetFree.free > 0)
                            'hoje cabe ${money(budgetFree.perDay)}',
                        ].join(' · ').ifEmpty('Toque para ver os lançamentos.'),
                  action: 'Ver',
                  onTap: () => openAnalysisEntries(
                      context,
                      yday.realized.where((t) => t.type == 'expense'),
                      'Gastos de ontem')));
            }
            // The first days of a month: invite to look back at the last one.
            if (today.day <= 5) {
              final last = DateTime(today.year, today.month - 1);
              insights.add(NexoInsight(
                  icon: Icons.auto_stories_outlined,
                  color: cs.primary,
                  title: 'Seu ${ptMonthYear(last).split(' ').first} em revisão',
                  subtitle: 'Quanto saiu, para onde foi e o que mudou.',
                  action: 'Ver',
                  onTap: () => _open(MonthReviewScreen(month: last))));
            }
            for (final alert in hidden
                ? const <ChargeAlert>[]
                : chargeAlerts(
                        transactions: app.transactions,
                        metadata: app.transactionMetadata,
                        recurring: app.recurring,
                        now: now,
                        dismissed: _dismissedAlerts)
                    .take(3)) {
              final first = alert.charges.first;
              insights.add(NexoInsight(
                  icon: switch (alert.kind) {
                    'duplicate' => Icons.content_copy_outlined,
                    'review' => Icons.policy_outlined,
                    _ => Icons.price_change_outlined,
                  },
                  color: NexoTones.warning(context),
                  title: switch (alert.kind) {
                    'duplicate' => 'Cobrança repetida: ${first.description}',
                    'review' => 'Cobrança para conferir: ${first.description}',
                    _ =>
                      '${alert.recurring!.name} veio ${money(alert.charges.last.amount)}',
                  },
                  subtitle: switch (alert.kind) {
                    'duplicate' =>
                      '${alert.charges.length}× ${money(first.amount)} em ${alert.charges.last.date.difference(first.date).inDays + 1} dia(s). Confira se é isso mesmo.',
                    'review' =>
                      '${money(first.amount)} em ${ptShortDate(first.date)}. Parece tarifa, seguro ou serviço do banco. Você contratou?',
                    _ => 'Previsto: ${money(alert.expected!)}. Mudou o preço?',
                  },
                  action: 'Ver',
                  onTap: () => _chargeAlert(app, alert)));
            }
            for (final card in app.accounts.where((a) => a.type == 'credit')) {
              final bank = BankSnapshots.linkedTo(_bank, card.id);
              final used = bank == null ? null : BankSnapshots.limitUsed(bank);
              if (used == null || used < .9) continue;
              insights.add(NexoInsight(
                  icon: Icons.credit_card_off_outlined,
                  color: NexoTones.expense(context),
                  title:
                      '${card.name}: ${(used * 100).round()}% do limite usado',
                  subtitle: hidden
                      ? 'Segundo o banco. Compras novas podem ser recusadas.'
                      : 'Disponível no banco: ${money(bank!.availableCents! / 100)}. Compras novas podem ser recusadas.',
                  action: 'Ver',
                  onTap: () => _open(CardInvoiceScreen(cardId: card.id))));
            }
            for (final r in app.recurring) {
              final days = _cancelIntents[r.id];
              if (days == null || !CancelIntents.due(r, days, now)) continue;
              insights.add(NexoInsight(
                  icon: Icons.cancel_schedule_send_outlined,
                  color: NexoTones.warning(context),
                  title:
                      'Cancele ${r.name} antes de ${ptShortDate(r.nextDate)}',
                  subtitle:
                      'Você marcou que não vai renovar. ${hidden ? '' : 'Próxima cobrança: ${money(r.amount)}.'}',
                  action: 'Abrir',
                  onTap: () => _open(RecurringDetailScreen(
                      recurring: r, fmt: (v) => analysisMoney(app, v)))));
            }
            // The carousel is for what matters now; the rest waits.
            final attention = insights.isEmpty
                ? null
                : NexoInsightCarousel(items: insights.take(4).toList());

            final futureCard = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _Heading('O que vem pela frente',
                      action: 'Agenda',
                      onTap: () => _open(AgendaScreen(initialDays: _horizon))),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    for (final days in [7, 30, 90])
                      ChoiceChip(
                          label: Text('$days dias'),
                          selected: _horizon == days,
                          onSelected: (_) => setState(() => _horizon = days))
                  ]),
                  const SizedBox(height: 14),
                  if (snapshot.hasError)
                    TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                            'Não foi possível carregar. Tentar novamente'))
                  else if (timeline == null)
                    const LinearProgressIndicator()
                  else ...[
                    _Value(
                        label:
                            'Saldo previsto em ${ptShortDate(timeline.points.last.date)}',
                        value: money(timeline.points.last.balance)),
                    const SizedBox(height: 12),
                    if (hidden)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child:
                              Text('Previsão visual oculta no modo privado.'))
                    else
                      CashTimelineChart(timeline: timeline, money: money),
                    const SizedBox(height: 12),
                    _Pair(
                        NexoStatPill(
                            icon: Icons.south_west,
                            label: 'A receber no período',
                            value: money(timeline.inflow),
                            valueColor: NexoTones.income(context)),
                        NexoStatPill(
                            icon: Icons.north_east,
                            label: 'A pagar no período',
                            value: money(timeline.outflow),
                            valueColor: NexoTones.expense(context))),
                    if (!hidden && timeline.lowest.balance < 0)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                              'Atenção ao caixa: ${money(timeline.lowest.balance)} em ${ptShortDate(timeline.lowest.date)}.',
                              style: TextStyle(
                                  color: cs.error,
                                  fontWeight: FontWeight.w700))),
                    const SizedBox(height: 8),
                    Text(
                        'Somente valores cadastrados, incluindo atrasados. Novas compras não estão previstas.',
                        style: Theme.of(context).textTheme.bodySmall),
                    if (forecast!.warnings.isNotEmpty)
                      TextButton(
                          onPressed: () =>
                              _open(AgendaScreen(initialDays: _horizon)),
                          child: const Text('Revisar dados da previsão')),
                    const Divider(height: 24),
                    Text('Próximos vencimentos',
                        style: Theme.of(context).textTheme.titleSmall),
                    if (timeline.upcoming.isEmpty)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                              'Nenhum vencimento cadastrado nos próximos $_horizon dias.')),
                    for (final e in timeline.upcoming.take(3))
                      _EventTile(
                          event: e,
                          now: today,
                          app: app,
                          onTap: () => _event(app, e)),
                    if (timeline.upcoming.length > 3)
                      TextButton(
                          onPressed: () =>
                              _open(AgendaScreen(initialDays: _horizon)),
                          child: Text(
                              'Ver os ${timeline.upcoming.length} vencimentos')),
                  ],
                ]));

            final categories = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _Heading('Para onde foi',
                      action: 'Análises',
                      onTap: () => _open(AnalysisScreen(initialMonth: month))),
                  Text(ptMonthYear(month),
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  if (data.expense == 0)
                    const Text(
                        'Sem despesas realizadas neste período. Registre uma despesa para começar a análise.')
                  else if (hidden)
                    const Text(
                        'Valores e distribuição ocultos no modo privado.')
                  else
                    NexoCategoryDonut(
                        slices: [
                          for (final e in data.topCategories)
                            NexoDonutSlice(
                                e.key,
                                app.categoryById(e.key)?.name ??
                                    'Sem categoria',
                                e.value,
                                Color(app.categoryById(e.key)?.colorValue ??
                                    0xFF607D8B)),
                        ],
                        total: data.expense,
                        money: money,
                        onSlice: (id) => _category(app, data, id)),
                  Wrap(spacing: 4, children: [
                    TextButton.icon(
                        onPressed: () => _open(MonthReviewScreen(month: month)),
                        icon: const Icon(Icons.auto_stories_outlined),
                        label: const Text('Mês em revisão')),
                    TextButton.icon(
                        onPressed: () => _open(
                            AnalysisScreen(initialMonth: month, closing: true)),
                        icon: const Icon(Icons.fact_check_outlined),
                        label: const Text('Fechamento')),
                  ]),
                ]));

            final budgetCard = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _Heading('Seus limites de agora',
                      action: 'Orçamentos',
                      onTap: () => _open(const BudgetScreen())),
                  if (budgets.isEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                        'Quanto você quer reservar para cada categoria? Defina um limite e acompanhe o restante aqui.'),
                    TextButton(
                        onPressed: () => _open(const BudgetScreen()),
                        child: const Text('Definir orçamentos')),
                  ],
                  for (final b in budgets.take(3))
                    _BudgetRow(
                        app: app,
                        budget: b,
                        onTap: () => _open(const BudgetScreen())),
                  if (budgets.isNotEmpty)
                    Text('Inclui pendências do período de cada orçamento.',
                        style: Theme.of(context).textTheme.bodySmall),
                ]));

            final cardRows =
                app.accounts.where((a) => a.type == 'credit').toList();
            final cards = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _Heading('Cartões e compromissos',
                      action: 'Ver tudo',
                      onTap: () => _open(const DebtOverviewScreen())),
                  if (cardRows.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Nenhum cartão cadastrado.')),
                  for (final card in cardRows.take(3))
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: _MiniCard(color: Color(card.colorValue)),
                        title: Text(card.name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            'Em aberto: ${money(app.convertToMain((-card.balance).clamp(0.0, double.infinity), card.currency))}\nFatura atual: ${snapshot.hasData ? money(currentInvoiceRemaining(card: card, now: now, transactions: app.transactions, metadata: app.transactionMetadata, payments: snapshot.data!, convert: app.convertToMain)) : 'indisponível'}${card.excludeFromTotal ? ' · fora do total' : ''}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _open(CardInvoiceScreen(cardId: card.id))),
                  if (app.loans.any((l) => !l.isSettled))
                    TextButton.icon(
                        onPressed: () => _open(const DebtOverviewScreen()),
                        icon: const Icon(Icons.account_balance),
                        label: Text(
                            '${app.loans.where((l) => !l.isSettled).length} empréstimos em aberto')),
                  Wrap(spacing: 4, children: [
                    TextButton.icon(
                        onPressed: () => _open(const AccountsScreen()),
                        icon: const Icon(Icons.account_balance_wallet_outlined),
                        label: const Text('Contas')),
                    TextButton.icon(
                        onPressed: () => _open(const TransferScreen()),
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('Transferir')),
                  ]),
                ]));

            // Same figure as the net worth screen: accounts plus assets.
            final netWorth = app.totalBalanceAll + app.totalAssetsValue;
            final history = [
              for (final snap in app.netWorthSnapshots.length > 90
                  ? app.netWorthSnapshots
                      .sublist(app.netWorthSnapshots.length - 90)
                  : app.netWorthSnapshots)
                snap.netWorth,
              netWorth,
            ];
            final monthAgo = app.netWorthSnapshots
                .where((s) =>
                    DateTime.tryParse(s.date)
                        ?.isBefore(today.subtract(const Duration(days: 29))) ==
                    true)
                .lastOrNull;
            final netChange =
                monthAgo == null ? null : netWorth - monthAgo.netWorth;
            final netWorthCard = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _Heading('Patrimônio',
                      action: 'Detalhes',
                      onTap: () => _open(const NetWorthScreen())),
                  _Amount(money(netWorth), size: 26),
                  if (netChange != null && !hidden)
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                            '${netChange >= 0 ? '▲' : '▼'} ${money(netChange.abs())} em 30 dias',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: netChange >= 0
                                    ? NexoTones.income(context)
                                    : NexoTones.expense(context)))),
                  const SizedBox(height: 10),
                  if (!hidden && history.length > 2)
                    NexoSparkline(values: history)
                  else
                    Text(
                        hidden
                            ? 'Evolução oculta no modo privado.'
                            : 'Contas e bens somados. A evolução aparece com o uso diário.',
                        style: Theme.of(context).textTheme.bodySmall),
                ]));

            final week = WeekSummary.build(
                transactions: app.transactions,
                metadata: app.transactionMetadata,
                amount: (t) => app.convertToMain(
                    t.amount,
                    t.currency.isEmpty
                        ? app.accountById(t.accountId)?.currency ??
                            app.settings.currency
                        : t.currency),
                now: today,
                weekStart: app.settings.weekStart);
            final weekCard = _Panel(
                child: _WeekBody(
                    week: week,
                    hidden: hidden,
                    money: money,
                    categoryName: (id) =>
                        app.categoryById(id)?.name ?? 'Categoria',
                    onReview: () => _open(const FinancialCheckupScreen())));

            final recent = app.transactions
                .where((t) => !t.date.isAfter(now))
                .toList()
              ..sort((a, b) => b.date.compareTo(a.date));
            final activity = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  _Heading('Últimos lançamentos',
                      action: 'Ver todos',
                      onTap: () => _open(const TransactionSearchScreen())),
                  if (recent.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                            'Comece registrando uma receita ou despesa pelos atalhos acima.')),
                  for (final t in recent.take(5))
                    Builder(builder: (context) {
                      final meta = app.transactionMetadata[t.id];
                      final neutral = FinanceRules.isNeutral(t, meta);
                      final pending = meta?.isPending == true;
                      final value = money(app.convertToMain(
                          t.amount,
                          t.currency.isEmpty
                              ? app.accountById(t.accountId)?.currency ??
                                  app.settings.currency
                              : t.currency));
                      final income = t.type == 'income';
                      return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: neutral
                              ? CircleAvatar(
                                  radius: 20,
                                  backgroundColor: cs.surfaceContainerHigh,
                                  child: const Icon(Icons.swap_horiz, size: 20))
                              : CategoryDot(
                                  category: app.categoryById(t.categoryId),
                                  size: 40),
                          title: Text(hidden ? 'Lançamento' : t.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                              '${ptShortDate(t.date)} · ${pending ? 'Pendente' : neutral ? 'Movimentação' : income ? 'Receita' : 'Despesa'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          trailing:
                              Row(mainAxisSize: MainAxisSize.min, children: [
                            // Large amounts shrink instead of taking the row.
                            ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 120),
                                child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                        hidden || neutral
                                            ? value
                                            : '${income ? '+' : '−'} $value',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontFeatures: NexoTones.figures,
                                            color: neutral || hidden
                                                ? null
                                                : income
                                                    ? NexoTones.income(context)
                                                    : pending
                                                        ? NexoTones.warning(
                                                            context)
                                                        : null)))),
                            if (!neutral)
                              PopupMenuButton<String>(
                                  tooltip: 'Ações do lançamento',
                                  onSelected: (v) => _open(v == 'repeat'
                                      ? AddTransactionScreen(
                                          template: t, initialType: t.type)
                                      : AddTransactionScreen(
                                          existing: t, initialType: t.type)),
                                  itemBuilder: (_) => const [
                                        PopupMenuItem(
                                            value: 'edit',
                                            child: Text('Editar')),
                                        PopupMenuItem(
                                            value: 'repeat',
                                            child: Text('Repetir como novo…'))
                                      ]),
                          ]),
                          onTap: neutral
                              ? null
                              : () => _open(AddTransactionScreen(
                                  existing: t, initialType: t.type)));
                    }),
                ]));

            // One row that scrolls: wrapping made three uneven lines.
            final links = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                child: Row(spacing: 8, children: [
                  for (final link in <(String, IconData, Widget)>[
                    (
                      'Análises',
                      Icons.bar_chart,
                      AnalysisScreen(initialMonth: month)
                    ),
                    ('Agenda', Icons.event_note, const AgendaScreen()),
                    (
                      'Revisão de 3 ou 7 dias',
                      Icons.fact_check_outlined,
                      const FinancialCheckupScreen()
                    ),
                    (
                      'Contas e cartões',
                      Icons.account_balance_wallet_outlined,
                      const AccountsScreen()
                    ),
                  ])
                    ActionChip(
                      avatar: Icon(link.$2, size: 18),
                      label: Text(link.$1),
                      onPressed: () => _open(link.$3),
                    ),
                ]));

            return LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              Widget row(Widget left, Widget right, {int flex = 1}) =>
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: flex, child: left),
                    const SizedBox(width: 20),
                    Expanded(flex: flex == 3 ? 2 : 1, child: right),
                  ]);
              const gap = SizedBox(height: 16);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        wide ? 24 : 16, 8, wide ? 24 : 16, 28),
                    child: Center(
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1760),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (app.accounts.isEmpty)
                                    Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: ListTile(
                                            tileColor: cs.secondaryContainer,
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(16)),
                                            title: const Text(
                                                'Comece pela sua conta'),
                                            subtitle: const Text(
                                                'Cadastre o saldo inicial para acompanhar seu dinheiro.'),
                                            trailing:
                                                const Icon(Icons.arrow_forward),
                                            onTap: () =>
                                                _open(const AccountsScreen()))),
                                  if (wide) ...[
                                    if (attention != null) ...[attention, gap],
                                    row(
                                        Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              kpis,
                                              const SizedBox(height: 12),
                                              spendCard,
                                              const SizedBox(height: 12),
                                              quick,
                                              const SizedBox(height: 8),
                                              links,
                                            ]),
                                        monthCard),
                                    const SizedBox(height: 20),
                                    row(futureCard, categories, flex: 3),
                                    const SizedBox(height: 20),
                                    row(
                                        Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              weekCard,
                                              gap,
                                              dailyCard,
                                              gap,
                                              netWorthCard,
                                              gap,
                                              budgetCard
                                            ]),
                                        cards),
                                  ] else ...[
                                    monthBar,
                                    const SizedBox(height: 8),
                                    kpis,
                                    const SizedBox(height: 12),
                                    spendCard,
                                    const SizedBox(height: 12),
                                    quick,
                                    const SizedBox(height: 4),
                                    links,
                                    const SizedBox(height: 12),
                                    if (attention != null) ...[attention, gap],
                                    dailyCard,
                                    gap,
                                    monthCard,
                                    gap,
                                    weekCard,
                                    gap,
                                    categories,
                                    gap,
                                    netWorthCard,
                                    gap,
                                    futureCard,
                                    gap,
                                    budgetCard,
                                    gap,
                                    cards,
                                  ],
                                  gap,
                                  activity,
                                  gap,
                                  OutlinedButton.icon(
                                      onPressed: () =>
                                          _open(const FinancialCheckupScreen()),
                                      icon: const Icon(
                                          Icons.description_outlined),
                                      label: const Text(
                                          'Minha revisão de 3 ou 7 dias')),
                                ])))),
              );
            });
          }),
    );
  }

  Future<void> _chargeAlert(AppProvider app, ChargeAlert alert) async {
    final action = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
                title: Text(switch (alert.kind) {
                  'duplicate' => 'Cobrança repetida',
                  'review' => 'Cobrança para conferir',
                  _ => 'Valor diferente do previsto',
                }),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (final t in alert.charges)
                    ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(t.description),
                        subtitle: Text(ptShortDate(t.date)),
                        trailing: Text(analysisMoney(app, t.amount))),
                  if (alert.kind == 'price')
                    Text(
                        'A recorrente prevê ${analysisMoney(app, alert.expected!)}.'),
                  if (alert.kind == 'review')
                    const Text(
                        'O aviso olha só a descrição. Se você não reconhece, peça ao banco o detalhamento; o Nexo não contesta nem cancela nada.'),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, 'ok'),
                      child: Text(
                          alert.kind == 'review' ? 'Reconheço' : 'Está certo')),
                  if (alert.kind == 'price')
                    TextButton(
                        onPressed: () => Navigator.pop(c, 'update'),
                        child: Text(
                            'Prever ${analysisMoney(app, alert.charges.last.amount)}')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, 'view'),
                      child: const Text('Ver lançamentos')),
                ]));
    if (!mounted || action == null) return;
    if (action == 'view') {
      openAnalysisEntries(
          context,
          alert.charges,
          switch (alert.kind) {
            'duplicate' => 'Cobrança repetida',
            'review' => 'Cobrança para conferir',
            _ => alert.recurring!.name,
          });
      return;
    }
    if (action == 'update') {
      final r = RecurringPayment.fromMap(alert.recurring!.toMap(),
          skippedOccurrences: alert.recurring!.skippedOccurrences)
        ..amount = alert.charges.last.amount;
      await app.updateRecurring(r);
    }
    await CancelIntents.dismissAlert(chargeAlertKey(alert));
    await _loadDismissed();
  }

  void _category(AppProvider app, FinancialAnalysis data, String id) =>
      openAnalysisEntries(
          context,
          data.realized.where((t) => t.type == 'expense' && t.categoryId == id),
          app.categoryById(id)?.name ?? 'Categoria');
}

/// "Quanto posso gastar": per day until the end of the month, and how the
/// number is made, so it can be trusted.
class _SpendableBody extends StatefulWidget {
  const _SpendableBody(
      {required this.s,
      required this.hidden,
      required this.money,
      required this.onSetup});
  final Spendable s;
  final bool hidden;
  final String Function(double) money;
  final VoidCallback onSetup;
  @override
  State<_SpendableBody> createState() => _SpendableBodyState();
}

class _SpendableBodyState extends State<_SpendableBody> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final money = widget.money;
    final cs = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    if (!s.hasBase) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quanto posso gastar',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text(
            'Cadastre sua renda fixa (salário, bolsa) como recorrente e o Nexo mostra quanto cabe por dia depois das contas e metas.'),
        TextButton(
            onPressed: widget.onSetup,
            child: const Text('Cadastrar renda fixa')),
      ]);
    }
    final over = s.free < 0;
    Widget row(String label, double value, {bool plus = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(label)),
          Text('${plus ? '+' : '−'} ${money(value)}',
              style: const TextStyle(fontFeatures: NexoTones.figures)),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
            child: Text('Quanto posso gastar',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800))),
        TextButton(
            onPressed: () => setState(() => _open = !_open),
            child: Text(_open ? 'Ocultar conta' : 'Como chego nisso')),
      ]),
      if (over) ...[
        // Said once, without shouting: the number and what is left out.
        Text('Renda fixa do mês já usada',
            style: TextStyle(
                color: NexoTones.warning(context),
                fontWeight: FontWeight.w800,
                fontSize: 16)),
        Text(
            '${money(-s.free)} além dela, com ${s.daysLeft} dia(s) pela frente. Renda extra e reserva não entram nesta conta.',
            style: small),
      ] else ...[
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: money(s.perDay),
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: cs.primary,
                      fontFeatures: NexoTones.figures)),
              const TextSpan(text: '  por dia'),
            ]))),
        Text('${money(s.free)} livres até o fim do mês · ${s.daysLeft} dia(s)',
            style: small),
      ],
      if (_open) ...[
        const Divider(height: 20),
        row('Renda fixa do mês', s.fixedIncome, plus: true),
        row('Contas fixas do mês', s.fixedBills),
        if (s.pendingBills > 0) row('Pendentes do mês', s.pendingBills),
        if (s.goals > 0) row('Guardar para metas', s.goals),
        row('Gasto variável até hoje', s.variableSpent),
        const SizedBox(height: 6),
        Text(
            'Renda extra, transferências e reservas não entram. Contas fixas e renda fixa vêm das recorrentes.',
            style: small),
      ],
    ]);
  }
}

/// This week so far: total, comparison, a bar per day and what stood out.
class _WeekBody extends StatelessWidget {
  const _WeekBody(
      {required this.week,
      required this.hidden,
      required this.money,
      required this.categoryName,
      required this.onReview});
  final WeekSummary week;
  final bool hidden;
  final String Function(double) money;
  final String Function(String id) categoryName;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final change = week.change;
    final up = (change ?? 0) > 0;
    final days = week.days;
    final peak = days.fold(0.0, math.max);
    final letters = week.start.weekday == DateTime.monday
        ? const ['S', 'T', 'Q', 'Q', 'S', 'S', 'D']
        : const ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
    final biggest = week.biggest;
    final top = week.topCategory;
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _Heading('Sua semana', action: 'Revisar', onTap: onReview),
      Text('${ptShortDate(week.start)} até hoje', style: small),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Amount(money(week.spent), size: 26),
          const SizedBox(height: 2),
          Text(
              hidden
                  ? 'Gasto na semana'
                  : change == null
                      ? 'Sem gastos no mesmo período da semana passada'
                      : change.abs() < 1
                          ? 'Igual ao mesmo período da semana passada'
                          : '${up ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}% vs. ${money(week.previousSpent)} na semana passada',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: hidden || change == null || change.abs() < 1
                      ? cs.onSurfaceVariant
                      : up
                          ? NexoTones.expense(context)
                          : NexoTones.income(context))),
        ])),
        if (!hidden)
          SizedBox(
              width: 132,
              height: 72,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                        Container(
                            height: peak <= 0
                                ? 3
                                : math.max(3, 40 * days[i] / peak),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                                color: i == week.daysElapsed - 1
                                    ? cs.primary
                                    : i < week.daysElapsed
                                        ? cs.primary.withValues(alpha: .45)
                                        : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(3))),
                        const SizedBox(height: 4),
                        Text(letters[i],
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: i == week.daysElapsed - 1
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: cs.onSurfaceVariant)),
                      ])),
              ])),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 16, runSpacing: 8, children: [
        _WeekFact(Icons.spa_outlined,
            '${week.quietDays} de ${week.daysElapsed} dia(s) sem gastos'),
        if (top != null && !hidden)
          _WeekFact(Icons.donut_small_outlined,
              '${categoryName(top.key)}: ${money(top.value)}'),
        if (biggest != null && !hidden)
          _WeekFact(Icons.north_east,
              'Maior: ${biggest.description} · ${money(week.amountOf(biggest))}'),
      ]),
    ]);
  }
}

class _WeekFact extends StatelessWidget {
  const _WeekFact(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Flexible(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5))),
      ]));
}

/// "Boa tarde, Daniel": the first name, or nothing.
String _greeting(String userName, {DateTime? now}) {
  final h = (now ?? DateTime.now()).hour;
  final part = h < 6
      ? 'Boa noite'
      : h < 12
          ? 'Bom dia'
          : h < 18
              ? 'Boa tarde'
              : 'Boa noite';
  final first = userName.trim().split(RegExp(r'\s+')).first;
  return first.isEmpty ? part : '$part, $first';
}

String _todayLabel({DateTime? now}) {
  final d = now ?? DateTime.now();
  final s = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// Change in usual spending against the previous period. The first weeks of
/// use have almost nothing behind them: a few entries would read as
/// thousands of percent, so the text says there is no base instead.
String _changeText(
    FinancialAnalysis data, FinancialAnalysis previous, String period) {
  final previousEntries =
      previous.realized.where((t) => t.type == 'expense').length;
  final change = data.changeFrom(previous);
  if (change == null || previousEntries < 3) {
    return 'Sem base no período anterior para comparar';
  }
  final oneOffs = data.extraordinary > 0 || previous.extraordinary > 0
      ? ', sem os pontuais'
      : '';
  if (change.abs() >= 200) {
    final times =
        (data.normal / previous.normal).toStringAsFixed(1).replaceAll('.', ',');
    return '$times× os gastos do período anterior $period$oneOffs';
  }
  final pct = change.abs().toStringAsFixed(1).replaceAll('.', ',');
  final dir = data.normal > previous.normal
      ? 'a mais'
      : data.normal < previous.normal
          ? 'a menos'
          : 'de variação';
  return '$pct% $dir em gastos $period$oneOffs';
}

/// One number with its label, flat, as the four on top of the home.
class _Kpi extends StatelessWidget {
  const _Kpi(
      {required this.label,
      required this.value,
      this.hint,
      this.color,
      this.big = false,
      this.onTap,
      this.onInfo});
  final String label, value;
  final String? hint;
  final Color? color;
  final bool big;
  final VoidCallback? onTap, onInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return NexoCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 12),
      child: InkWell(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant))),
            if (onInfo != null)
              IconButton(
                  tooltip: 'Entender os valores',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: onInfo,
                  icon: Icon(Icons.info_outline,
                      size: 18, color: cs.onSurfaceVariant))
            else
              const SizedBox(height: 28),
          ]),
          FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: TextStyle(
                      fontSize: big ? 24 : 20,
                      fontWeight: FontWeight.w900,
                      color: color,
                      fontFeatures: NexoTones.figures))),
          if (hint != null)
            Text(hint!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});
  @override
  Widget build(BuildContext context) => NexoCard(child: child);
}

class _Legend extends StatelessWidget {
  final Color color;
  final String label;
  final bool dashed;
  const _Legend(
      {required this.color, required this.label, this.dashed = false});
  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 14,
            height: 3,
            decoration: BoxDecoration(
                color: dashed ? null : color,
                border: dashed
                    ? Border(top: BorderSide(color: color, width: 2))
                    : null,
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]);
}

/// Card-shaped badge in the card's own color.
class _MiniCard extends StatelessWidget {
  final Color color;
  const _MiniCard({required this.color});
  @override
  Widget build(BuildContext context) => Container(
      width: 46,
      height: 32,
      decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color,
            Color.lerp(color, Colors.black, .35)!,
          ], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(7)),
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(5),
      child: Container(
          width: 9,
          height: 7,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .75),
              borderRadius: BorderRadius.circular(2))));
}

class _Heading extends StatelessWidget {
  final String title, action;
  final VoidCallback onTap;
  const _Heading(this.title, {required this.action, required this.onTap});
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800))),
        TextButton(onPressed: onTap, child: Text(action)),
      ]);
}

class _Pair extends StatelessWidget {
  final Widget a, b;
  const _Pair(this.a, this.b);
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        if (c.maxWidth / MediaQuery.textScalerOf(context).scale(1) < 230) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [a, const SizedBox(height: 12), b]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: a),
          const SizedBox(width: 12),
          Expanded(child: b)
        ]);
      });
}

class _Amount extends StatelessWidget {
  final String value;
  final double size;
  const _Amount(this.value, {this.size = 22});
  @override
  Widget build(BuildContext context) => SizedBox(
      width: double.infinity,
      child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.4,
                  fontFeatures: NexoTones.figures))));
}

class _Value extends StatelessWidget {
  final String label, value;
  final String? detail;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  const _Value(
      {required this.label,
      required this.value,
      this.detail,
      this.icon,
      this.color,
      this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 4)
              ],
              Expanded(
                  child:
                      Text(label, style: TextStyle(fontSize: 12, color: color)))
            ]),
            const SizedBox(height: 4),
            _Amount(value, size: 22),
            if (detail != null)
              Text(detail!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
          ])));
}

class _EventTile extends StatelessWidget {
  final ForecastEvent event;
  final DateTime now;
  final AppProvider app;
  final VoidCallback onTap;
  const _EventTile(
      {required this.event,
      required this.now,
      required this.app,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final days = event.date.difference(now).inDays;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('${event.date.day}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(DateFormat('MMM', 'pt_BR').format(event.date),
                    style: const TextStyle(fontSize: 10))
              ]))),
      title: Text(app.settings.hideBalance ? 'Compromisso' : event.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${days == 0 ? 'Hoje' : days == 1 ? 'Amanhã' : 'Em $days dias'} · ${event.amount < 0 ? 'A pagar' : 'A receber'}'),
        Text(
            analysisMoney(
                app, app.convertToMain(event.amount.abs(), event.currency)),
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ]),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

class _BudgetRow extends StatelessWidget {
  final AppProvider app;
  final Budget budget;
  final VoidCallback onTap;
  const _BudgetRow(
      {required this.app, required this.budget, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final spent = app.budgetSpent(budget);
    final limit = app.budgetLimit(budget);
    final left = limit - spent;
    return InkWell(
        onTap: onTap,
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  '${app.categoryById(budget.categoryId)?.name ?? 'Categoria'} · ${budget.period == 'weekly' ? 'semana' : 'mês'}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                  '${left < 0 ? 'Excedido' : 'Ainda disponível'} ${analysisMoney(app, left.abs())}'),
              if (!app.settings.hideBalance && limit > 0) ...[
                const SizedBox(height: 8),
                NexoProgress(value: spent / limit),
              ],
              const SizedBox(height: 4),
              Text(
                  '${analysisMoney(app, spent)} de ${analysisMoney(app, limit)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ])));
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
