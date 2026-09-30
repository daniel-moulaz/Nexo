import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/cash_forecast.dart';
import '../services/financial_analysis.dart';
import '../widgets/analysis_widgets.dart';
import 'analysis_screen.dart';
import 'add_transaction_screen.dart';
import 'agenda_screen.dart';
import 'budget_screen.dart';
import 'notification_inbox_screen.dart';
import 'transaction_search_screen.dart';
import 'transfer_screen.dart';

class FinanceHomeScreen extends StatefulWidget {
  const FinanceHomeScreen({super.key});
  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> {
  Future<List<Map<String, dynamic>>>? payments;
  List<AppTransaction>? lastTransactions;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final txs = context.watch<AppProvider>().transactions;
    if (!identical(lastTransactions, txs)) {
      lastTransactions = txs;
      payments =
          DBHelper.database.then((db) => db.query('card_invoice_payments'));
    }
  }

  void open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final now = DateTime.now();
    final filter = FinancialAnalysis.month(now, now);
    final data = analyzePeriod(app, filter);
    final previous = analyzePeriod(
        app, FinancialAnalysis.previousMonth(filter, partial: true));
    final change = data.changeFrom(previous);
    String money(double v) => analysisMoney(app, v);
    final cash = app.cashAccounts
        .where((a) => !a.excludeFromTotal)
        .fold<double>(
            0, (s, a) => s + app.convertToMain(a.balance, a.currency));
    final budgets = app.budgets.toList()
      ..sort((a, b) => (b.amount == 0 ? 0.0 : app.budgetSpent(b) / b.amount)
          .compareTo(a.amount == 0 ? 0.0 : app.budgetSpent(a) / a.amount));
    final summary = AnalysisCard(
        title: 'Seu mês • ${DateFormat('MMMM', 'pt_BR').format(now)}',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Saldo em contas'),
          Text(money(cash),
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          AnalysisMetrics(values: [
            ('Receitas realizadas', money(data.income)),
            ('Gastos realizados', money(data.expense))
          ]),
          const SizedBox(height: 12),
          Text(app.settings.hideBalance
              ? 'Comparação oculta'
              : change == null
                  ? 'Mês anterior sem gastos para comparar'
                  : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% de gastos até o dia ${now.day}, comparado ao mesmo intervalo do mês anterior'),
          if (!app.settings.hideBalance && data.topCategories.isNotEmpty)
            Text(
                'Maior gasto: ${app.categoryById(data.topCategories.first.key)?.name ?? 'Sem categoria'} • ${money(data.topCategories.first.value)}'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: () =>
                    open(const AddTransactionScreen(initialType: 'expense')),
                icon: const Icon(Icons.add),
                label: const Text('Despesa')),
            OutlinedButton(
                onPressed: () =>
                    open(const AddTransactionScreen(initialType: 'income')),
                child: const Text('Receita')),
            IconButton(
                tooltip: 'Transferir entre contas',
                onPressed: () => open(const TransferScreen()),
                icon: const Icon(Icons.swap_horiz)),
          ]),
        ]));
    final forecast = AnalysisCard(
        title: 'Quanto fica disponível?',
        action: IconButton(
            tooltip: 'Ver agenda e previsão',
            onPressed: () => open(const AgendaScreen()),
            icon: const Icon(Icons.arrow_forward)),
        child: FutureBuilder<List<Map<String, dynamic>>>(
            future: payments,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return TextButton(
                    onPressed: () => setState(() {
                          payments = DBHelper.database
                              .then((db) => db.query('card_invoice_payments'));
                        }),
                    child: const Text(
                        'Não foi possível carregar. Tentar novamente'));
              if (!snapshot.hasData) return const LinearProgressIndicator();
              CashForecast at(DateTime end) => CashForecast.calculate(
                  now: now,
                  until: end,
                  accounts: app.accounts,
                  transactions: app.transactions,
                  recurring: app.recurring,
                  metadata: app.transactionMetadata,
                  invoicePayments: snapshot.data!,
                  convert: app.convertToMain);
              final week = at(DateTime(now.year, now.month, now.day + 7));
              final end = at(DateTime(now.year, now.month + 1, 0));
              final committed = end.events
                  .where((e) => e.amount < 0)
                  .fold<double>(
                      0, (s, e) => s - app.convertToMain(e.amount, e.currency));
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnalysisMetrics(values: [
                      ('Previsto em 7 dias', money(week.projected)),
                      ('Previsto no fim do mês', money(end.projected))
                    ]),
                    const SizedBox(height: 12),
                    Text(
                        'Saídas previstas até o fim do mês: ${money(committed)}'),
                    const Text(
                        'Inclui compromissos e receitas cadastrados, inclusive atrasados. Não é um limite seguro de gasto; novas compras não estão previstas.'),
                    if (end.warnings.isNotEmpty)
                      TextButton(
                          onPressed: () => open(const AgendaScreen()),
                          child: const Text('Há dados a revisar na previsão')),
                    for (final e
                        in week.events.where((e) => e.amount != 0).take(2))
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(app.settings.hideBalance
                              ? 'Compromisso'
                              : e.title),
                          subtitle: Text(DateFormat('dd/MM').format(e.date)),
                          trailing: Text(
                              money(app.convertToMain(e.amount, e.currency))),
                          onTap: () => open(const AgendaScreen())),
                    if (week.events.where((e) => e.amount != 0).isEmpty)
                      const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                              'Sem compromissos cadastrados nos próximos 7 dias.')),
                  ]);
            }));
    final categories = AnalysisCard(
        title: 'Para onde foi meu dinheiro',
        action: IconButton(
            tooltip: 'Abrir Análises',
            onPressed: () => open(const AnalysisScreen()),
            icon: const Icon(Icons.arrow_forward)),
        child: CategoryBreakdown(
            app: app,
            data: data,
            compact: true,
            onCategory: (id) => openAnalysisEntries(
                context,
                data.realized
                    .where((t) => t.type == 'expense' && t.categoryId == id),
                app.categoryById(id)?.name ?? 'Categoria')));
    final budget = AnalysisCard(
        title: 'Disponível nos orçamentos',
        action: IconButton(
            tooltip: 'Todos os orçamentos',
            onPressed: () => open(const BudgetScreen()),
            icon: const Icon(Icons.arrow_forward)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (budgets.isEmpty)
            const Text(
                'Defina limites por categoria para acompanhar quanto ainda pode gastar.'),
          for (final b in budgets.take(3))
            Builder(builder: (context) {
              final spent = app.budgetSpent(b);
              return InkWell(
                  onTap: () => open(const BudgetScreen()),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${app.categoryById(b.categoryId)?.name ?? 'Categoria'} • ${b.period == 'weekly' ? 'semana' : 'mês'}'),
                            Text('${money(spent)} / ${money(b.amount)}'),
                            if (!app.settings.hideBalance && b.amount > 0) ...[
                              const SizedBox(height: 6),
                              LinearProgressIndicator(
                                  value: (spent / b.amount).clamp(0, 1)),
                              const SizedBox(height: 4),
                              Text(
                                  '${(spent / b.amount * 100).toStringAsFixed(0)}% • ${spent > b.amount ? 'Excedido' : 'Restante'} ${money((b.amount - spent).abs())}')
                            ],
                          ])));
            }),
          const Text(
              'Inclui despesas pendentes; cada limite vale para sua categoria.'),
        ]));
    return Scaffold(
        appBar: AppBar(
            automaticallyImplyLeading: false,
            title: const Text('Nexo'),
            actions: [
              IconButton(
                  tooltip: 'Buscar lançamentos',
                  onPressed: () => open(const TransactionSearchScreen()),
                  icon: const Icon(Icons.search)),
              IconButton(
                  tooltip: app.settings.hideBalance
                      ? 'Mostrar valores'
                      : 'Ocultar valores',
                  onPressed: () => app.updateSetting(
                      'hideBalance', !app.settings.hideBalance),
                  icon: Icon(app.settings.hideBalance
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined)),
            ]),
        body: LayoutBuilder(
            builder: (context, size) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Column(children: [
                          summary,
                          const SizedBox(height: 12),
                          Row(children: [
                            for (final action in const [
                              ('Análises', Icons.bar_chart, AnalysisScreen()),
                              (
                                'Sugestões',
                                Icons.inbox_outlined,
                                NotificationInboxScreen()
                              ),
                              ('Agenda', Icons.event_note, AgendaScreen()),
                            ])
                              Expanded(
                                  child: TextButton(
                                      onPressed: () => open(action.$3),
                                      child: Column(children: [
                                        Icon(action.$2),
                                        const SizedBox(height: 4),
                                        Text(action.$1)
                                      ]))),
                          ]),
                          const SizedBox(height: 12),
                          if (size.maxWidth >= 1000)
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: Column(children: [
                                    forecast,
                                    const SizedBox(height: 16),
                                    budget
                                  ])),
                                  const SizedBox(width: 16),
                                  Expanded(child: categories)
                                ])
                          else ...[
                            forecast,
                            const SizedBox(height: 16),
                            categories,
                            const SizedBox(height: 16),
                            budget
                          ],
                        ]))))));
  }
}
