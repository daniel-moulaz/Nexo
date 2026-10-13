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
import '../utils/finance_input.dart';
import '../widgets/analysis_widgets.dart';
import '../widgets/cash_timeline_chart.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
    if (mounted) await _refresh();
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
          title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nexo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontWeight: FontWeight.w900)),
                Text('Seu dinheiro, com clareza',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12)),
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
                  (b.amount <= 0 ? 0.0 : app.budgetSpent(b) / b.amount)
                      .compareTo(
                          a.amount <= 0 ? 0.0 : app.budgetSpent(a) / a.amount));

            final hero = _Panel(
                color: cs.primaryContainer,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Expanded(
                            child: Text('Saldo em contas · hoje',
                                style: TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(
                            tooltip: 'Entender os valores',
                            visualDensity: VisualDensity.compact,
                            onPressed: _explain,
                            icon: const Icon(Icons.info_outline, size: 20)),
                      ]),
                      InkWell(
                          onTap: () => _open(const AccountsScreen()),
                          child: _Amount(money(commitment.cash), size: 34)),
                      const SizedBox(height: 10),
                      _Pair(
                          _Value(
                              label: 'Cartões em aberto',
                              value: money(commitment.outstanding),
                              small: true,
                              onTap: () => _open(const DebtOverviewScreen())),
                          _Value(
                              label: 'Após cartões',
                              value: money(commitment.available),
                              small: true,
                              onTap: _explain)),
                      Divider(
                          color: cs.onPrimaryContainer.withValues(alpha: .15)),
                      InkWell(
                          onTap: () =>
                              _open(const AgendaScreen(initialDays: -1)),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(children: [
                                const Icon(Icons.trending_up, size: 20),
                                const SizedBox(width: 8),
                                const Expanded(
                                    child: Text('Previsão no fim do mês',
                                        style: TextStyle(fontSize: 12))),
                                Flexible(
                                    child: Text(
                                        monthEnd == null
                                            ? '—'
                                            : money(monthEnd.projected),
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold))),
                                const Icon(Icons.chevron_right, size: 18),
                              ]))),
                    ]));

            final monthCard = _Panel(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    IconButton(
                        tooltip: 'Mês anterior',
                        onPressed: () => setState(() =>
                            _month = DateTime(month.year, month.month - 1)),
                        icon: const Icon(Icons.chevron_left)),
                    Expanded(
                        child: Column(children: [
                      Text(ptMonthYear(month),
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(currentMonth ? 'Até hoje' : 'Mês completo',
                          style: Theme.of(context).textTheme.labelSmall),
                    ])),
                    IconButton(
                        tooltip: 'Próximo mês',
                        onPressed: currentMonth
                            ? null
                            : () => setState(() =>
                                _month = DateTime(month.year, month.month + 1)),
                        icon: const Icon(Icons.chevron_right)),
                  ]),
                  const SizedBox(height: 4),
                  _Pair(
                      _Value(
                          label: 'Entrou',
                          value: money(data.income),
                          icon: Icons.south_west,
                          color: cs.primary,
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
                      _Value(
                          label: 'Gastou',
                          value: money(data.expense),
                          icon: Icons.north_east,
                          color: cs.error,
                          onTap: () => openAnalysisEntries(
                              context,
                              data.realized.where((t) => t.type == 'expense'),
                              'Despesas · ${ptMonthYear(month)}'))),
                  const SizedBox(height: 8),
                  if (!app.settings.hideBalance)
                    _Comparison(
                        current: data.expense,
                        previous: previous.expense,
                        money: money),
                  if (!app.settings.hideBalance)
                    Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                            data.changeFrom(previous) == null
                                ? 'Sem gastos no período anterior para comparar'
                                : '${data.changeFrom(previous)!.abs().toStringAsFixed(1).replaceAll('.', ',')}% ${data.expense > previous.expense ? 'a mais' : data.expense < previous.expense ? 'a menos' : 'de variação'} em gastos ${currentMonth ? 'até o dia ${today.day}' : 'no mês'}',
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
                  if (data.topCategories.isNotEmpty &&
                      !app.settings.hideBalance)
                    Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: InkWell(
                            onTap: () => _category(
                                app, data, data.topCategories.first.key),
                            child: Text(
                                'Maior gasto: ${app.categoryById(data.topCategories.first.key)?.name ?? 'Sem categoria'} · ${money(data.topCategories.first.value)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)))),
                  if (!currentMonth)
                    TextButton(
                        onPressed: () => setState(() => _month = null),
                        child: const Text('Voltar para este mês')),
                ]));

            final actions = LayoutBuilder(builder: (context, constraints) {
              final columns = MediaQuery.textScalerOf(context).scale(1) > 1.4 &&
                      constraints.maxWidth < 450
                  ? 2
                  : 4;
              return Wrap(spacing: 8, runSpacing: 8, children: [
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
                  (
                    'Dívidas',
                    Icons.account_balance_outlined,
                    const DebtOverviewScreen()
                  ),
                  ('Recorrentes', Icons.event_repeat, const RecurringScreen()),
                ])
                  SizedBox(
                      width:
                          (constraints.maxWidth - 8 * (columns - 1)) / columns,
                      child: _QuickAction(
                          label: action.$1,
                          icon: action.$2,
                          primary: action.$1 == 'Despesa',
                          onTap: () => _open(action.$3))),
              ]);
            });

            final attention = overdue.isEmpty
                ? null
                : Material(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(18),
                    child: ListTile(
                      leading: Icon(Icons.notification_important_outlined,
                          color: cs.onErrorContainer),
                      title: Text(
                          '${overdue.length} ${overdue.length == 1 ? 'vencimento em atraso' : 'vencimentos em atraso'}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: cs.onErrorContainer)),
                      subtitle: Text(
                          '${money(overdue.fold<double>(0, (s, e) => s - app.convertToMain(e.amount, e.currency)))} · revisar na agenda',
                          style: TextStyle(color: cs.onErrorContainer)),
                      trailing:
                          Icon(Icons.chevron_right, color: cs.onErrorContainer),
                      onTap: () => _open(const AgendaScreen()),
                    ));

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
                    if (app.settings.hideBalance)
                      const Padding(
                          padding: EdgeInsets.all(16),
                          child:
                              Text('Previsão visual oculta no modo privado.'))
                    else
                      CashTimelineChart(timeline: timeline, money: money),
                    const SizedBox(height: 12),
                    _Pair(
                        _Value(
                            label: 'A receber no período',
                            value: money(timeline.inflow),
                            small: true),
                        _Value(
                            label: 'A pagar no período',
                            value: money(timeline.outflow),
                            small: true)),
                    if (!app.settings.hideBalance &&
                        timeline.lowest.balance < 0)
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
                  CategoryBreakdown(
                      app: app,
                      data: data,
                      compact: true,
                      onCategory: (id) => _category(app, data, id)),
                  TextButton.icon(
                      onPressed: () => _open(
                          AnalysisScreen(initialMonth: month, closing: true)),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('Ver fechamento do mês')),
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
                        leading: CircleAvatar(
                            backgroundColor:
                                Color(card.colorValue).withValues(alpha: .15),
                            child: const Icon(Icons.credit_card)),
                        title: Text(card.name),
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
                  for (final t in recent.take(4))
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            app.settings.hideBalance
                                ? 'Lançamento'
                                : t.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${ptShortDate(t.date)} · ${app.transactionMetadata[t.id]?.isPending == true ? 'Pendente' : FinanceRules.isNeutral(t, app.transactionMetadata[t.id]) ? 'Movimentação' : t.type == 'income' ? 'Receita' : 'Despesa'}'),
                              Text(
                                  money(app.convertToMain(
                                      t.amount,
                                      t.currency.isEmpty
                                          ? app
                                                  .accountById(t.accountId)
                                                  ?.currency ??
                                              app.settings.currency
                                          : t.currency)),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                            ]),
                        trailing: FinanceRules.isNeutral(
                                t, app.transactionMetadata[t.id])
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: 'Ações do lançamento',
                                onSelected: (v) => _open(v == 'repeat'
                                    ? AddTransactionScreen(
                                        template: t, initialType: t.type)
                                    : AddTransactionScreen(
                                        existing: t, initialType: t.type)),
                                itemBuilder: (_) => [
                                      const PopupMenuItem(
                                          value: 'edit', child: Text('Editar')),
                                      const PopupMenuItem(
                                          value: 'repeat',
                                          child: Text('Repetir como novo…'))
                                    ]),
                        onTap: FinanceRules.isNeutral(
                                t, app.transactionMetadata[t.id])
                            ? null
                            : () => _open(AddTransactionScreen(
                                existing: t, initialType: t.type))),
                ]));

            return LayoutBuilder(builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1050;
              Widget row(Widget left, Widget right, {int flex = 1}) =>
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: flex, child: left),
                    const SizedBox(width: 20),
                    Expanded(flex: flex == 3 ? 2 : 1, child: right),
                  ]);
              return RefreshIndicator(
                onRefresh: _refresh,
                child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(
                        wide ? 24 : 16, 12, wide ? 24 : 16, 28),
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
                                  if (wide)
                                    row(hero, monthCard)
                                  else ...[
                                    hero,
                                    const SizedBox(height: 12),
                                    monthCard
                                  ],
                                  const SizedBox(height: 12),
                                  actions,
                                  if (attention != null) ...[
                                    const SizedBox(height: 12),
                                    attention
                                  ],
                                  const SizedBox(height: 20),
                                  if (wide) ...[
                                    row(futureCard, categories, flex: 3),
                                    const SizedBox(height: 20),
                                    row(budgetCard, cards),
                                  ] else ...[
                                    futureCard,
                                    const SizedBox(height: 16),
                                    categories,
                                    const SizedBox(height: 16),
                                    budgetCard,
                                    const SizedBox(height: 16),
                                    cards,
                                  ],
                                  const SizedBox(height: 16),
                                  activity,
                                  const SizedBox(height: 16),
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

  void _category(AppProvider app, FinancialAnalysis data, String id) =>
      openAnalysisEntries(
          context,
          data.realized.where((t) => t.type == 'expense' && t.categoryId == id),
          app.categoryById(id)?.name ?? 'Categoria');
}

class _Panel extends StatelessWidget {
  final Widget child;
  final Color? color;
  const _Panel({required this.child, this.color});
  @override
  Widget build(BuildContext context) => Material(
      color: color ?? Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(24),
      child: Padding(padding: const EdgeInsets.all(18), child: child));
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
                  letterSpacing: -.4))));
}

class _Value extends StatelessWidget {
  final String label, value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final bool small;
  const _Value(
      {required this.label,
      required this.value,
      this.icon,
      this.color,
      this.onTap,
      this.small = false});
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
            _Amount(value, size: small ? 17 : 22),
          ])));
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;
  const _QuickAction(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.primary = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
        color: primary ? cs.primary : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
                child: Column(children: [
                  Icon(icon, color: primary ? cs.onPrimary : cs.primary),
                  const SizedBox(height: 4),
                  Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: primary ? cs.onPrimary : cs.onSurface))
                ]))));
  }
}

class _Comparison extends StatelessWidget {
  final double current, previous;
  final String Function(double) money;
  const _Comparison(
      {required this.current, required this.previous, required this.money});
  @override
  Widget build(BuildContext context) {
    final max = math.max(math.max(current, previous), 1.0);
    final cs = Theme.of(context).colorScheme;
    return Semantics(
        label:
            'Gastos do período ${money(current)}. Período anterior ${money(previous)}.',
        child: Column(children: [
          for (final item in [
            ('Período', current, cs.primary),
            ('Anterior', previous, cs.outlineVariant)
          ])
            Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(children: [
                  SizedBox(
                      width: 64,
                      child:
                          Text(item.$1, style: const TextStyle(fontSize: 11))),
                  Expanded(
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                              value: (item.$2 / max).clamp(0, 1),
                              color: item.$3,
                              backgroundColor: cs.surfaceContainerHighest,
                              minHeight: 6))),
                ])),
        ]));
  }
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
    final left = budget.amount - spent;
    final cs = Theme.of(context).colorScheme;
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
              if (!app.settings.hideBalance && budget.amount > 0) ...[
                const SizedBox(height: 8),
                ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                        minHeight: 6,
                        value: (spent / budget.amount).clamp(0, 1),
                        color: left < 0 ? cs.error : cs.primary)),
              ],
              const SizedBox(height: 4),
              Text(
                  '${analysisMoney(app, spent)} de ${analysisMoney(app, budget.amount)}',
                  style: Theme.of(context).textTheme.bodySmall),
            ])));
  }
}
