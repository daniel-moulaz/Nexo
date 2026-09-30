import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/financial_analysis.dart';
import '../services/transaction_metadata_service.dart';
import '../widgets/analysis_widgets.dart';
import 'add_transaction_screen.dart';
import 'net_worth_screen.dart';
import 'finance_export_screen.dart';

FinancialAnalysis analyzePeriod(AppProvider app, AnalysisFilter filter) =>
    FinancialAnalysis(
        transactions: app.transactions,
        metadata: app.transactionMetadata,
        filter: filter,
        amount: (t) => app.convertToMain(
            t.amount,
            t.currency.isEmpty
                ? app.accountById(t.accountId)?.currency ??
                    app.settings.currency
                : t.currency));

void openAnalysisEntries(
    BuildContext context, Iterable<AppTransaction> rows, String title) {
  Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => AnalysisEntriesScreen(
              ids: rows.map((t) => t.id).toSet(), title: title)));
}

class AnalysisScreen extends StatefulWidget {
  final DateTime? initialMonth;
  final bool closing;
  const AnalysisScreen({super.key, this.initialMonth, this.closing = false});
  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  late DateTime month;
  DateTimeRange? custom;
  String? account, category, subcategory, type;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = widget.initialMonth ??
        DateTime(now.year, now.month - (widget.closing ? 1 : 0));
  }

  AnalysisFilter get filter {
    final base = FinancialAnalysis.month(month, DateTime.now());
    return AnalysisFilter(
        from: custom?.start ?? base.from,
        to: custom?.end ?? base.to,
        accountId: account,
        categoryId: category,
        subcategory: subcategory,
        type: type);
  }

  Future<void> filters(AppProvider app) async {
    var a = account, c = category, s = subcategory, t = type;
    final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
              Widget choice(
                      String label,
                      String? value,
                      Map<String, String> options,
                      void Function(String?) change) =>
                  DropdownButtonFormField<String>(
                      key: ValueKey('$label:$value'),
                      initialValue: options.containsKey(value) ? value : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: label),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Todos')),
                        for (final e in options.entries)
                          DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value,
                                  overflow: TextOverflow.ellipsis))
                      ],
                      onChanged: (v) => update(() => change(v)));
              return AlertDialog(
                  title: const Text('Filtrar análises'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    choice(
                        'Conta ou cartão',
                        a,
                        {for (final v in app.accounts) v.id: v.name},
                        (v) => a = v),
                    choice('Categoria', c,
                        {for (final v in app.categories) v.id: v.name}, (v) {
                      c = v;
                      s = null;
                    }),
                    choice(
                        'Subcategoria',
                        s,
                        {
                          for (final tx in app.transactions)
                            if (c == null || tx.categoryId == c)
                              if (app.transactionMetadata[tx.id]?.subcategory
                                      .isNotEmpty ==
                                  true)
                                app.transactionMetadata[tx.id]!.subcategory:
                                    app.transactionMetadata[tx.id]!.subcategory
                        },
                        (v) => s = v),
                    choice(
                        'Tipo',
                        t,
                        {
                          'expense': 'Despesas',
                          'income': 'Receitas e reembolsos'
                        },
                        (v) => t = v),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Aplicar'))
                  ]);
            }));
    if (accepted == true && mounted)
      setState(() {
        account = a;
        category = c;
        subcategory = s;
        type = t;
      });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final f = filter;
    final data = analyzePeriod(app, f);
    final partial = month.year == DateTime.now().year &&
        month.month == DateTime.now().month;
    final previousFilter = custom == null
        ? FinancialAnalysis.previousMonth(f, partial: partial)
        : f.period(
            f.from.subtract(Duration(days: f.to.difference(f.from).inDays + 1)),
            f.from.subtract(const Duration(days: 1)));
    final previous = analyzePeriod(app, previousFilter);
    final change = data.changeFrom(previous);
    String money(double v) => analysisMoney(app, v);
    String period(AnalysisFilter v) =>
        '${DateFormat('dd/MM/yy').format(v.from)} – ${DateFormat('dd/MM/yy').format(v.to)}';
    final months =
        List.generate(6, (i) => DateTime(f.to.year, f.to.month - 5 + i));
    final history = [
      for (final m in months)
        analyzePeriod(
            app, f.period(m, FinancialAnalysis.month(m, DateTime.now()).to))
    ];
    final comparison = app.settings.hideBalance
        ? 'Comparação oculta'
        : change == null
            ? 'Sem base percentual no período anterior'
            : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% nas despesas';
    final panels = <Widget>[
      AnalysisCard(
          title: widget.closing
              ? 'Fechamento • ${DateFormat('MMMM yyyy', 'pt_BR').format(month)}'
              : 'Resumo do período',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnalysisMetrics(values: [
              ('Receitas realizadas', money(data.income)),
              ('Despesas realizadas', money(data.expense)),
              ('Reembolsos identificados', money(data.refunds)),
              ('Resultado do período', money(data.result))
            ]),
            const SizedBox(height: 16),
            if (widget.closing) ...[
              Text(partial
                  ? 'Fechamento parcial: mês em andamento.'
                  : 'Resumo recalculado a partir dos registros atuais; não bloqueia edições.'),
              Text(app.settings.hideBalance
                  ? 'Maior categoria oculta'
                  : data.topCategories.isEmpty
                      ? 'Sem despesas registradas'
                      : 'Maior categoria: ${app.categoryById(data.topCategories.first.key)?.name ?? 'Sem categoria'}'),
              const SizedBox(height: 8),
            ],
            Text(comparison),
            Text('Comparação: ${period(f)} com ${period(previousFilter)}'),
            const SizedBox(height: 8),
            Text(
                'Pendências registradas: ${money(data.pendingExpense)} • Transferências de saída: ${money(data.transfers)}'),
            const SizedBox(height: 8),
            const Text(
                'Compras no cartão contam na data da compra; pagar a fatura não gera outra despesa. Resultado = receitas + reembolsos − despesas; não é o saldo bancário.'),
            TextButton.icon(
                onPressed: () => openAnalysisEntries(
                    context, data.realized, 'Lançamentos do período'),
                icon: const Icon(Icons.receipt_long),
                label: Text('Ver ${data.realized.length} lançamentos')),
          ])),
      AnalysisCard(
          title: 'Para onde foi meu dinheiro',
          child: CategoryBreakdown(
              app: app,
              data: data,
              onCategory: (id) => openAnalysisEntries(
                  context,
                  data.realized
                      .where((t) => t.type == 'expense' && t.categoryId == id),
                  app.categoryById(id)?.name ?? 'Sem categoria'))),
      AnalysisCard(
          title: 'Receitas × despesas • 6 meses',
          child: app.settings.hideBalance
              ? const Text('Gráfico oculto no modo privado.')
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text(
                      'Azul: receitas • laranja: despesas. Toque em um mês para abrir os lançamentos.'),
                  const SizedBox(height: 16),
                  SizedBox(
                      height: 200,
                      child: BarChart(BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                              topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              leftTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false)),
                              bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      getTitlesWidget: (value, meta) => Text(
                                          DateFormat('MM/yy').format(months[
                                              value.toInt().clamp(0, 5)]))))),
                          barTouchData:
                              BarTouchData(touchCallback: (event, response) {
                            final i = response?.spot?.touchedBarGroupIndex;
                            if (event is FlTapUpEvent && i != null)
                              openAnalysisEntries(context, history[i].realized,
                                  DateFormat('MM/yyyy').format(months[i]));
                          }),
                          barGroups: [
                            for (var i = 0; i < 6; i++)
                              BarChartGroupData(x: i, barRods: [
                                BarChartRodData(
                                    toY: history[i].income,
                                    color: Colors.blue.shade700,
                                    width: 9),
                                BarChartRodData(
                                    toY: history[i].expense,
                                    color: Colors.deepOrange.shade700,
                                    width: 9)
                              ])
                          ]))),
                  // Text equivalents support accessibility and exact values without touch.
                  for (var i = 0; i < 6; i++)
                    ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            DateFormat('MMMM yyyy', 'pt_BR').format(months[i])),
                        subtitle: Text(
                            'Receitas ${money(history[i].income)} • despesas ${money(history[i].expense)}'),
                        onTap: () => openAnalysisEntries(
                            context,
                            history[i].realized,
                            DateFormat('MM/yyyy').format(months[i]))),
                  Text(
                      'Média de despesas nos 5 meses anteriores: ${money(history.take(5).fold<double>(0, (s, d) => s + d.expense) / 5)}. Meses sem registros contam como zero.'),
                ])),
      AnalysisCard(
          title: 'Composição das despesas',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AnalysisMetrics(values: [
              ('Normal', money(data.normal)),
              ('Extraordinário', money(data.extraordinary)),
              ('Origem recorrente', money(data.recurring)),
              ('Demais despesas', money(data.variable))
            ]),
            const SizedBox(height: 12),
            const Text(
                'Recorrente é a origem registrada do lançamento; não presume que toda despesa fixa esteja cadastrada. Reembolsos sem vínculo não são abatidos de categorias.'),
          ])),
      AnalysisCard(
          title: 'Subcategorias',
          child: breakdown(
              context,
              app,
              data.subcategories,
              (id) => id.isEmpty ? 'Sem subcategoria' : id,
              (id) => data.realized.where((t) =>
                  t.type == 'expense' &&
                  (app.transactionMetadata[t.id]?.subcategory ?? '') == id))),
      AnalysisCard(
          title: 'Contas e cartões • consumo',
          child: breakdown(
              context,
              app,
              data.accounts,
              (id) => app.accountById(id)?.name ?? 'Conta removida',
              (id) => data.realized
                  .where((t) => t.type == 'expense' && t.accountId == id))),
      if (account == null &&
          category == null &&
          subcategory == null &&
          type == null &&
          custom == null)
        AnalysisCard(
            title: 'Orçado × realizado',
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text(
                  'Limites mensais atuais, comparados ao mês selecionado. Inclui pendências; não é um histórico dos limites antigos.'),
              if (app.budgets.where((b) => b.period == 'monthly').isEmpty)
                const Text(
                    'Cadastre um orçamento para acompanhar o restante por categoria.'),
              for (final b in app.budgets.where((b) => b.period == 'monthly'))
                Builder(builder: (context) {
                  final spent = analyzePeriod(
                      app,
                      AnalysisFilter(
                          from: DateTime(month.year, month.month),
                          to: DateTime(month.year, month.month + 1, 0),
                          categoryId: b.categoryId));
                  final total = spent.expense + spent.pendingExpense;
                  return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          app.categoryById(b.categoryId)?.name ?? 'Categoria'),
                      subtitle: Text(
                          '${money(total)} / ${money(b.amount)} • ${total > b.amount ? 'Excedido' : 'Restante'} ${money((b.amount - total).abs())}'),
                      onTap: () => openAnalysisEntries(
                          context,
                          [...spent.realized, ...spent.pending],
                          'Orçamento da categoria'));
                }),
            ])),
    ];
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.closing ? 'Fechamento mensal' : 'Análises'),
            actions: [
              IconButton(
                  tooltip: 'Patrimônio',
                  icon: const Icon(Icons.account_balance),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const NetWorthScreen()))),
              IconButton(
                  tooltip: 'Exportar relatório',
                  icon: const Icon(Icons.file_download_outlined),
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const FinanceExportScreen()))),
            ]),
        body: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Column(children: [
                          Row(children: [
                            IconButton(
                                tooltip: 'Mês anterior',
                                icon: const Icon(Icons.chevron_left),
                                onPressed: () => setState(() {
                                      custom = null;
                                      month =
                                          DateTime(month.year, month.month - 1);
                                    })),
                            Expanded(
                                child: Text(
                                    custom == null
                                        ? DateFormat('MMMM yyyy', 'pt_BR')
                                            .format(month)
                                        : period(f),
                                    textAlign: TextAlign.center)),
                            IconButton(
                                tooltip: 'Próximo mês',
                                icon: const Icon(Icons.chevron_right),
                                onPressed: () => setState(() {
                                      custom = null;
                                      month =
                                          DateTime(month.year, month.month + 1);
                                    }))
                          ]),
                          if (!widget.closing)
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              OutlinedButton.icon(
                                  onPressed: () => filters(app),
                                  icon: const Icon(Icons.filter_list),
                                  label: const Text('Filtros')),
                              OutlinedButton.icon(
                                  onPressed: () async {
                                    final range = await showDateRangePicker(
                                        context: context,
                                        firstDate: DateTime(1900),
                                        lastDate: DateTime(2200),
                                        initialDateRange: DateTimeRange(
                                            start: f.from, end: f.to));
                                    if (range != null && mounted)
                                      setState(() => custom = range);
                                  },
                                  icon: const Icon(Icons.date_range),
                                  label: const Text('Período')),
                              if (account != null ||
                                  category != null ||
                                  subcategory != null ||
                                  type != null ||
                                  custom != null)
                                TextButton(
                                    onPressed: () => setState(() {
                                          account = category =
                                              subcategory = type = null;
                                          custom = null;
                                        }),
                                    child: const Text('Limpar filtros')),
                              TextButton(
                                  onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => AnalysisScreen(
                                              initialMonth: month,
                                              closing: true))),
                                  child: const Text('Fechamento mensal')),
                            ]),
                          if (account != null ||
                              category != null ||
                              subcategory != null ||
                              type != null)
                            Padding(
                                padding: const EdgeInsets.all(8),
                                child: Text([
                                  if (account != null)
                                    app.accountById(account!)?.name ??
                                        'Conta indisponível',
                                  if (category != null)
                                    app.categoryById(category!)?.name ??
                                        'Categoria indisponível',
                                  if (subcategory != null) subcategory!,
                                  if (type != null)
                                    type == 'expense'
                                        ? 'Despesas'
                                        : 'Receitas e reembolsos'
                                ].join(' • '))),
                          const SizedBox(height: 12),
                          if (constraints.maxWidth < 1000) ...[
                            for (final p in panels)
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: p)
                          ] else ...[
                            panels.first,
                            const SizedBox(height: 16),
                            Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                      child: Column(children: [
                                    for (var i = 1; i < panels.length; i += 2)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 16),
                                          child: panels[i])
                                  ])),
                                  const SizedBox(width: 16),
                                  Expanded(
                                      child: Column(children: [
                                    for (var i = 2; i < panels.length; i += 2)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 16),
                                          child: panels[i])
                                  ]))
                                ])
                          ],
                        ]))))));
  }

  Widget breakdown(
      BuildContext context,
      AppProvider app,
      Map<String, double> values,
      String Function(String) name,
      Iterable<AppTransaction> Function(String) rows) {
    if (values.isEmpty) return const Text('Sem despesas neste período.');
    final entries = values.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(children: [
      for (final e in entries)
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(name(e.key)),
            subtitle: Text(analysisMoney(app, e.value)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openAnalysisEntries(context, rows(e.key), name(e.key)))
    ]);
  }
}

class AnalysisEntriesScreen extends StatelessWidget {
  final Set<String> ids;
  final String title;
  const AnalysisEntriesScreen(
      {super.key, required this.ids, required this.title});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final rows = app.transactions.where((t) => ids.contains(t.id)).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    void edit(AppTransaction tx) => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) =>
                AddTransactionScreen(existing: tx, initialType: tx.type)));
    return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: rows.isEmpty
            ? const Center(child: Text('Nenhum lançamento neste recorte.'))
            : LayoutBuilder(
                builder: (context, size) => size.maxWidth >= 900
                    ? SingleChildScrollView(
                        child: SizedBox(
                            width: size.maxWidth,
                            child: DataTable(columns: const [
                              DataColumn(label: Text('Data')),
                              DataColumn(label: Text('Descrição')),
                              DataColumn(label: Text('Conta / cartão')),
                              DataColumn(label: Text('Valor'), numeric: true),
                              DataColumn(label: Text('Editar'))
                            ], rows: [
                              for (final tx in rows)
                                DataRow(cells: [
                                  DataCell(Text(DateFormat('dd/MM/yyyy')
                                      .format(tx.date))),
                                  DataCell(SizedBox(
                                      width: 240,
                                      child: Text(
                                          app.settings.hideBalance
                                              ? 'Lançamento'
                                              : tx.description,
                                          overflow: TextOverflow.ellipsis))),
                                  DataCell(Text(
                                      app.accountById(tx.accountId)?.name ??
                                          '')),
                                  DataCell(Text(analysisMoney(
                                      app,
                                      app.convertToMain(
                                          tx.amount,
                                          tx.currency.isEmpty
                                              ? app
                                                      .accountById(tx.accountId)
                                                      ?.currency ??
                                                  app.settings.currency
                                              : tx.currency)))),
                                  DataCell(IconButton(
                                      tooltip: 'Editar lançamento',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => edit(tx)))
                                ])
                            ])))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final tx = rows[i];
                          final meta = app.transactionMetadata[tx.id] ??
                              TransactionMetadata(transactionId: tx.id);
                          return ListTile(
                              title: Text(app.settings.hideBalance
                                  ? 'Lançamento'
                                  : tx.description),
                              subtitle: Text(
                                  '${DateFormat('dd/MM/yyyy').format(tx.date)} • ${app.accountById(tx.accountId)?.name ?? ''}${meta.isPending ? ' • Pendente' : ''}'),
                              trailing: Text(analysisMoney(
                                  app,
                                  app.convertToMain(
                                      tx.amount,
                                      tx.currency.isEmpty
                                          ? app
                                                  .accountById(tx.accountId)
                                                  ?.currency ??
                                              app.settings.currency
                                          : tx.currency))),
                              onTap: () => edit(tx));
                        })));
  }
}
