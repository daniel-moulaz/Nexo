import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:fl_chart/fl_chart.dart';
import '../investments/investment_models.dart';
import '../investments/investment_repository.dart';
import '../investments/investment_quotes.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import '../widgets/analysis_widgets.dart';

String _money(BuildContext context, int cents) =>
    context.read<AppProvider>().settings.hideBalance
        ? '••••'
        : formatAmount(cents / 100, 'BRL');
String _quantity(int units) =>
    NumberFormat('0.######', 'pt_BR').format(units / investmentScale);
const _trackingNotice =
    'Carteira de acompanhamento em reais. Compras, vendas e proventos aqui não alteram suas contas, receitas ou despesas. Não some esta carteira a saldos que já incluem esses investimentos.';

class InvestmentsScreen extends StatefulWidget {
  const InvestmentsScreen({super.key});
  @override
  State<InvestmentsScreen> createState() => _InvestmentsScreenState();
}

class _InvestmentsScreenState extends State<InvestmentsScreen> {
  final repository = InvestmentRepository();
  late Future<List<InvestmentPosition>> _data;
  bool _refreshing = false;
  String _search = '', _class = 'Todas';
  String? _quoteStatus;
  @override
  void initState() {
    super.initState();
    _data = repository.load();
    InvestmentRepository.revision.addListener(_reload);
    _autoQuotes();
  }

  @override
  void dispose() {
    InvestmentRepository.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted)
      setState(() {
        _data = repository.load();
      });
  }

  Future<void> _autoQuotes() async {
    try {
      if (await InvestmentQuoteSettings.enabled() && mounted) await _quotes();
    } catch (_) {
      if (mounted)
        setState(() => _quoteStatus =
            'Não foi possível ler a configuração de cotações. A carteira continua disponível.');
    }
  }

  Future<void> _quotes() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      if (!await InvestmentQuoteSettings.enabled()) {
        if (mounted) await _settings();
        return;
      }
      final positions = (await repository.load())
          .where((p) => p.quantity > 0 && p.investment.canQuote)
          .toList();
      if (positions.isEmpty) {
        if (mounted)
          setState(() => _quoteStatus =
              'Cadastre uma ação brasileira com ticker para consultar. Demais classes usam preço manual nesta versão.');
        return;
      }
      if (!await InvestmentQuoteSettings.claimRefresh()) {
        if (mounted)
          setState(() => _quoteStatus =
              'Consultas limitadas a uma rodada a cada 15 minutos. Os últimos valores continuam disponíveis.');
        return;
      }
      final token = await InvestmentQuoteSettings.token();
      var updated = 0;
      String? failure;
      // Deduplicate tickers and serialize requests for the free API plan.
      final tickers = positions.map((p) => p.investment.ticker).toSet();
      for (final ticker in tickers.take(20)) {
        if (!mounted) break;
        try {
          final quote = await InvestmentQuotes().fetch(ticker, token: token);
          for (final p
              in positions.where((p) => p.investment.ticker == ticker)) {
            await repository.price(
                p.investment.id, quote.priceMicros, quote.date, 'brapi');
          }
          updated++;
        } on QuoteFailure catch (e) {
          failure = e.message;
          break;
        }
      }
      if (mounted)
        setState(() => _quoteStatus =
            '$updated código(s) consultado(s). ${failure ?? (tickers.length > 20 ? 'Limite de 20 códigos por rodada.' : 'Confira a data de cada preço; cotações podem ter atraso.')}');
    } catch (_) {
      if (mounted)
        setState(() => _quoteStatus =
            'Falha ao consultar ou salvar cotações. Você pode continuar usando a carteira offline.');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _settings() async {
    await showDialog<void>(
        context: context, builder: (_) => const _QuoteSettingsDialog());
  }

  Future<void> _create() async {
    await showDialog<void>(
        context: context, builder: (_) => const _OperationDialog());
  }

  @override
  Widget build(BuildContext context) {
    final private = context.watch<AppProvider>().settings.hideBalance;
    return Scaffold(
      appBar: AppBar(title: const Text('Investimentos'), actions: [
        IconButton(
            tooltip: 'Configurar cotações',
            onPressed: _settings,
            icon: const Icon(Icons.settings_outlined)),
        IconButton(
            tooltip: 'Atualizar cotações',
            onPressed: _refreshing ? null : _quotes,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh)),
      ]),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar investimento')),
      body: FutureBuilder<List<InvestmentPosition>>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Não foi possível carregar a carteira.'),
                TextButton(
                    onPressed: _reload, child: const Text('Tentar novamente'))
              ]));
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final all = snapshot.data!;
            final shown = all
                .where((p) =>
                    (_class == 'Todas' || p.investment.assetClass == _class) &&
                    '${p.investment.name} ${p.investment.ticker} ${p.investment.institution}'
                        .toLowerCase()
                        .contains(_search.toLowerCase()))
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));
            int sum(int Function(InvestmentPosition) pick) =>
                all.fold(0, (v, p) => v + pick(p));
            final groups = <String, int>{};
            for (final p in all.where((p) => p.value > 0)) {
              groups.update(p.investment.assetClass, (v) => v + p.value,
                  ifAbsent: () => p.value);
            }
            final now = DateTime.now();
            final monthly = all
                .expand((p) => p.operations)
                .where((o) =>
                    o.kind == 'buy' &&
                    o.date.toLocal().year == now.year &&
                    o.date.toLocal().month == now.month)
                .fold(0, (v, o) => v + o.cents);
            return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1440),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AnalysisCard(
                                  title: 'Sua carteira · BRL',
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        AnalysisMetrics(values: [
                                          (
                                            'Valor de referência',
                                            _money(context, sum((p) => p.value))
                                          ),
                                          (
                                            'Custo da posição',
                                            _money(context, sum((p) => p.cost))
                                          )
                                        ]),
                                        const SizedBox(height: 12),
                                        _PositionChange(
                                          change: sum((p) => p.unrealized),
                                          cost: sum((p) => p.cost),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                            'Variação sobre o custo da posição atual, sem vendas e proventos. Não é o rendimento do dia.'),
                                      ])),
                              if (_quoteStatus != null)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    child: Text(_quoteStatus!)),
                              if (all.isEmpty)
                                Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 32),
                                    child: Column(children: [
                                      const Icon(Icons.show_chart, size: 56),
                                      const SizedBox(height: 12),
                                      Text('Seu próximo passo começa aqui',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge),
                                      const SizedBox(height: 8),
                                      const Text(
                                          'Cadastre o que você já tem ou registre sua primeira compra. Separe o que aportou da valorização e acompanhe a distribuição da carteira.',
                                          textAlign: TextAlign.center),
                                      TextButton(
                                          onPressed: _create,
                                          child: const Text(
                                              'Cadastrar primeiro investimento')),
                                    ])),
                              if (all.isNotEmpty) ...[
                                const SizedBox(height: 16),
                                const SizedBox(height: 16),
                                TextField(
                                    decoration: const InputDecoration(
                                        labelText:
                                            'Buscar ativo ou instituição',
                                        prefixIcon: Icon(Icons.search)),
                                    onChanged: (v) =>
                                        setState(() => _search = v)),
                                const SizedBox(height: 12),
                                Wrap(spacing: 8, children: [
                                  for (final c in [
                                    'Todas',
                                    ...investmentClasses
                                  ])
                                    ChoiceChip(
                                        label: Text(c),
                                        selected: c == _class,
                                        onSelected: (_) =>
                                            setState(() => _class = c))
                                ]),
                                const SizedBox(height: 12),
                                if (shown.isEmpty)
                                  const Text(
                                      'Nenhum investimento neste filtro.'),
                                for (final p in shown)
                                  _PositionCard(
                                    position: p,
                                    onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) => _InvestmentDetail(
                                                id: p.investment.id))),
                                  ),
                                const SizedBox(height: 24),
                                LayoutBuilder(builder: (context, c) {
                                  final allocation = AnalysisCard(
                                      title: 'Distribuição por classe',
                                      child: private
                                          ? const Text(
                                              'Distribuição oculta no modo privado.')
                                          : _Allocation(
                                              groups: groups,
                                              onClass: (v) =>
                                                  setState(() => _class = v)));
                                  final results = AnalysisCard(
                                      title: 'Resultados registrados',
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            AnalysisMetrics(values: [
                                              (
                                                'Vendas: ganho/perda',
                                                _money(context,
                                                    sum((p) => p.realized))
                                              ),
                                              (
                                                'Proventos recebidos',
                                                _money(context,
                                                    sum((p) => p.income))
                                              ),
                                              (
                                                'Compras neste mês',
                                                _money(context, monthly)
                                              )
                                            ]),
                                            const SizedBox(height: 12),
                                            const Text(
                                                'Custo médio nas vendas. Informe valores líquidos de taxas. Sem apuração de impostos, recomendação de compra ou comparação com CDI.'),
                                          ]));
                                  if (c.maxWidth < 800)
                                    return Column(children: [
                                      allocation,
                                      const SizedBox(height: 12),
                                      results
                                    ]);
                                  return Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: allocation),
                                        const SizedBox(width: 16),
                                        Expanded(child: results)
                                      ]);
                                }),
                              ],
                              const SizedBox(height: 16),
                              const Text(_trackingNotice),
                            ]))));
          }),
    );
  }
}

String _source(Investment i) => '${switch (i.priceSource) {
      'brapi' => 'brapi',
      'entrada' => 'Preço de entrada',
      _ => 'Preço manual'
    }} · ${ptDate(i.priceAt.toLocal())}';

/// Price return on remaining cost, deliberately not time-weighted performance.
class _PositionChange extends StatelessWidget {
  final int change, cost;
  const _PositionChange({required this.change, required this.cost});

  @override
  Widget build(BuildContext context) {
    final private = context.watch<AppProvider>().settings.hideBalance;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = private || change == 0
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : change > 0
            ? (dark ? const Color(0xff69dbad) : const Color(0xff146c43))
            : (dark ? const Color(0xffffa4a4) : const Color(0xffb3261e));
    final sign = change > 0
        ? '+'
        : change < 0
            ? '−'
            : '';
    final percent = cost > 0
        ? '$sign${NumberFormat('0.00', 'pt_BR').format(change.abs() * 100 / cost)}%'
        : 'Sem base percentual';
    return Semantics(
      label: 'Variação da posição',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                  private || change == 0
                      ? Icons.horizontal_rule
                      : change > 0
                          ? Icons.trending_up
                          : Icons.trending_down,
                  size: 20,
                  color: color),
              Text(private ? '••••' : '$sign${_money(context, change.abs())}',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800)),
              if (!private)
                Text(percent,
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w700)),
              Text(
                  private
                      ? 'Variação oculta'
                      : change > 0
                          ? 'Ganho na posição'
                          : change < 0
                              ? 'Perda na posição'
                              : 'Sem variação',
                  style: TextStyle(color: color, fontSize: 12)),
            ]),
      ),
    );
  }
}

class _PositionCard extends StatelessWidget {
  final InvestmentPosition position;
  final VoidCallback onTap;
  const _PositionCard({required this.position, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = position;
    final private = context.watch<AppProvider>().settings.hideBalance;
    final average = p.quantity == 0
        ? null
        : roundedRatio(p.cost, investmentScale, p.quantity);
    final price = private
        ? '••••'
        : NumberFormat.currency(
                locale: 'pt_BR',
                symbol: 'R\$',
                decimalDigits: p.investment.priceMicros % 10000 == 0 ? 2 : 6)
            .format(p.investment.priceMicros / investmentScale);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    if (p.investment.ticker.isNotEmpty)
                      Text(p.investment.ticker,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                    Text(p.investment.name,
                        style: TextStyle(
                            fontWeight: p.investment.ticker.isEmpty
                                ? FontWeight.w800
                                : FontWeight.normal)),
                    Text(
                        '${p.investment.assetClass} · ${p.quantity == 0 ? 'Posição encerrada' : private ? '••••' : '${_quantity(p.quantity)} unidades'}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
              const Icon(Icons.chevron_right),
            ]),
            const SizedBox(height: 12),
            if (p.quantity > 0)
              _PositionChange(change: p.unrealized, cost: p.cost)
            else
              Text('Resultado das vendas: ${_money(context, p.realized)}'),
            const SizedBox(height: 12),
            AnalysisMetrics(values: [
              ('Valor atual', _money(context, p.value)),
              ('Custo da posição', _money(context, p.cost)),
              (
                'Preço médio',
                private
                    ? '••••'
                    : average == null
                        ? '—'
                        : _money(context, average)
              ),
              ('Último preço', price),
            ]),
            const SizedBox(height: 8),
            Text(_source(p.investment),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

class _Allocation extends StatelessWidget {
  final Map<String, int> groups;
  final ValueChanged<String> onClass;
  const _Allocation({required this.groups, required this.onClass});
  @override
  Widget build(BuildContext context) {
    final total = groups.values.fold(0, (a, b) => a + b);
    if (total == 0) return const Text('Sem posições com valor positivo.');
    final entries = groups.entries.toList();
    const colors = [
      Colors.blue,
      Colors.teal,
      Colors.orange,
      Colors.purple,
      Colors.pink,
      Colors.indigo
    ];
    return Column(children: [
      SizedBox(
          height: 170,
          child: PieChart(PieChartData(
              centerSpaceRadius: 42,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                      value: entries[i].value.toDouble(),
                      color: colors[i],
                      radius: 34,
                      showTitle: false)
              ],
              pieTouchData: PieTouchData(touchCallback: (event, response) {
                final index =
                    response?.touchedSection?.touchedSectionIndex ?? -1;
                if (event is FlTapUpEvent &&
                    index >= 0 &&
                    index < entries.length) onClass(entries[index].key);
              })))),
      for (var i = 0; i < entries.length; i++)
        ListTile(
            dense: true,
            leading: Icon(Icons.circle, size: 14, color: colors[i]),
            title: Text(entries[i].key),
            subtitle: Text(
                '${(entries[i].value / total * 100).toStringAsFixed(1).replaceAll('.', ',')}% · ${_money(context, entries[i].value)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onClass(entries[i].key)),
    ]);
  }
}

class _InvestmentDetail extends StatefulWidget {
  final String id;
  const _InvestmentDetail({required this.id});
  @override
  State<_InvestmentDetail> createState() => _InvestmentDetailState();
}

class _InvestmentDetailState extends State<_InvestmentDetail> {
  final repository = InvestmentRepository();
  late Future<List<InvestmentPosition>> data;
  @override
  void initState() {
    super.initState();
    data = repository.load();
    InvestmentRepository.revision.addListener(reload);
  }

  void reload() {
    if (mounted)
      setState(() {
        data = repository.load();
      });
  }

  @override
  void dispose() {
    InvestmentRepository.revision.removeListener(reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final private = context.watch<AppProvider>().settings.hideBalance;
    return Scaffold(
        appBar: AppBar(title: const Text('Detalhes do investimento')),
        body: FutureBuilder<List<InvestmentPosition>>(
            future: data,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Center(
                    child: TextButton(
                        onPressed: reload,
                        child:
                            const Text('Falha ao carregar. Tentar novamente')));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final p = snapshot.data!
                  .where((p) => p.investment.id == widget.id)
                  .firstOrNull;
              if (p == null)
                return const Center(
                    child: Text('Investimento não encontrado.'));
              return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1000),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(p.investment.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                Text(
                                    '${p.investment.assetClass} · ${p.investment.institution} ${p.investment.ticker}'),
                                const SizedBox(height: 16),
                                AnalysisMetrics(values: [
                                  (
                                    'Valor de referência',
                                    _money(context, p.value)
                                  ),
                                  ('Custo restante', _money(context, p.cost)),
                                  (
                                    'Quantidade',
                                    private ? '••••' : _quantity(p.quantity)
                                  ),
                                  (
                                    'Preço médio',
                                    private
                                        ? '••••'
                                        : p.quantity == 0
                                            ? '—'
                                            : _money(
                                                context,
                                                roundedRatio(
                                                    p.cost,
                                                    investmentScale,
                                                    p.quantity))
                                  )
                                ]),
                                const SizedBox(height: 12),
                                if (p.quantity > 0)
                                  _PositionChange(
                                      change: p.unrealized, cost: p.cost),
                                const SizedBox(height: 12),
                                Text(_source(p.investment)),
                                if (DateTime.now()
                                        .difference(p.investment.priceAt) >
                                    const Duration(days: 2))
                                  const Text(
                                      'Preço antigo: atualize antes de usar este valor para uma decisão.'),
                                const SizedBox(height: 16),
                                Wrap(spacing: 12, runSpacing: 8, children: [
                                  FilledButton.icon(
                                      onPressed: () => showDialog<void>(
                                          context: context,
                                          builder: (_) =>
                                              _OperationDialog(position: p)),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Registrar operação')),
                                  OutlinedButton.icon(
                                      onPressed: () => showDialog<void>(
                                          context: context,
                                          builder: (_) =>
                                              _PriceDialog(position: p)),
                                      icon: const Icon(Icons.edit_outlined),
                                      label: const Text('Informar preço')),
                                ]),
                                const SizedBox(height: 20),
                                const Text(_trackingNotice),
                                const SizedBox(height: 24),
                                Text('Histórico',
                                    style:
                                        Theme.of(context).textTheme.titleLarge),
                                if (p.operations.isEmpty)
                                  const Text(
                                      'Sem operações. Registre uma compra para começar.'),
                                for (final op in p.operations.reversed)
                                  Card(
                                      child: ListTile(
                                          title: Text(op.label),
                                          subtitle: Text(
                                              '${ptDate(op.date.toLocal())} · ${_money(context, op.cents)}${op.kind == 'income' ? '' : ' · ${private ? '••••' : _quantity(op.quantity)} un.'}'),
                                          trailing: IconButton(
                                              tooltip: 'Excluir operação',
                                              icon: const Icon(
                                                  Icons.delete_outline),
                                              onPressed: () async {
                                                final confirmed = await showDialog<
                                                        bool>(
                                                    context: context,
                                                    builder: (ctx) =>
                                                        AlertDialog(
                                                            title: const Text(
                                                                'Excluir esta operação?'),
                                                            content: const Text(
                                                                'A posição será recalculada. Suas contas bancárias não serão alteradas. A exclusão será bloqueada se deixar alguma venda sem quantidade.'),
                                                            actions: [
                                                              TextButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          ctx,
                                                                          false),
                                                                  child: const Text(
                                                                      'Cancelar')),
                                                              FilledButton(
                                                                  onPressed: () =>
                                                                      Navigator.pop(
                                                                          ctx,
                                                                          true),
                                                                  child: const Text(
                                                                      'Excluir'))
                                                            ]));
                                                if (confirmed != true) return;
                                                try {
                                                  await repository
                                                      .removeOperation(op.id);
                                                  if (context.mounted)
                                                    _message(context,
                                                        'Operação excluída; posição recalculada.');
                                                } on FormatException catch (e) {
                                                  if (context.mounted)
                                                    _message(
                                                        context, e.message);
                                                } catch (_) {
                                                  if (context.mounted)
                                                    _message(context,
                                                        'Não foi possível excluir. Tente novamente.');
                                                }
                                              }))),
                              ]))));
            }));
  }
}

void _message(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));

class _OperationDialog extends StatefulWidget {
  final InvestmentPosition? position;
  const _OperationDialog({this.position});
  @override
  State<_OperationDialog> createState() => _OperationDialogState();
}

class _OperationDialogState extends State<_OperationDialog> {
  final name = TextEditingController(),
      ticker = TextEditingController(),
      institution = TextEditingController(),
      quantity = TextEditingController(),
      amount = TextEditingController();
  final id = const Uuid().v4(), assetId = const Uuid().v4();
  String assetClass = 'Ações', kind = 'opening';
  DateTime date = DateTime.now();
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    if (widget.position != null) kind = 'buy';
  }

  @override
  void dispose() {
    for (final c in [name, ticker, institution, quantity, amount]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final units = kind == 'income' ? 0 : parseInvestmentQuantity(quantity.text);
    final value = parseMoney(amount.text);
    if (units == null ||
        value == null ||
        value < 0 ||
        (widget.position == null && name.text.trim().isEmpty)) {
      setState(() => error =
          'Preencha nome, quantidade válida e valor total. Use vírgula para decimais.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final op = InvestmentOperation(
          id: id,
          investmentId: widget.position?.investment.id ?? assetId,
          kind: kind,
          quantity: units,
          cents: (value * 100).round(),
          date: date,
          createdAt: DateTime.now());
      final repository = InvestmentRepository();
      if (widget.position == null) {
        await repository.create(
            Investment(
                id: assetId,
                name: name.text.trim(),
                assetClass: assetClass,
                ticker: ticker.text.trim().toUpperCase(),
                institution: institution.text.trim(),
                priceMicros: roundedRatio(op.cents, 10000000000, units),
                priceAt: date,
                priceSource: 'entrada'),
            op);
      } else {
        await repository.record(op);
      }
      if (mounted) {
        Navigator.pop(context);
        _message(
            context, 'Operação registrada na carteira. Contas preservadas.');
      }
    } on FormatException catch (e) {
      if (mounted) setState(() => error = e.message);
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Não foi possível salvar. Seus dados anteriores foram preservados.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.position == null
              ? 'Adicionar investimento'
              : 'Registrar operação'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    if (widget.position == null) ...[
                      TextField(
                          controller: name,
                          maxLength: 120,
                          decoration: const InputDecoration(
                              labelText: 'Nome do investimento'),
                          textInputAction: TextInputAction.next),
                      DropdownButtonFormField<String>(
                          initialValue: assetClass,
                          isExpanded: true,
                          decoration:
                              const InputDecoration(labelText: 'Classe'),
                          items: [
                            for (final c in investmentClasses)
                              DropdownMenuItem(value: c, child: Text(c))
                          ],
                          onChanged: (v) => setState(() => assetClass = v!)),
                      TextField(
                          controller: ticker,
                          maxLength: 12,
                          textCapitalization: TextCapitalization.characters,
                          decoration: const InputDecoration(
                              labelText: 'Ticker (opcional)',
                              helperText:
                                  'Ex.: PETR4. Cotações online: ações brasileiras.')),
                      TextField(
                          controller: institution,
                          maxLength: 120,
                          decoration: const InputDecoration(
                              labelText:
                                  'Corretora ou instituição (opcional)')),
                    ],
                    DropdownButtonFormField<String>(
                        initialValue: kind,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Operação'),
                        items: [
                          if (widget.position == null)
                            const DropdownMenuItem(
                                value: 'opening',
                                child: Text('Posição que já possuo')),
                          const DropdownMenuItem(
                              value: 'buy', child: Text('Compra / aporte')),
                          if (widget.position != null) ...[
                            const DropdownMenuItem(
                                value: 'sell', child: Text('Venda / resgate')),
                            const DropdownMenuItem(
                                value: 'income',
                                child: Text('Provento recebido'))
                          ]
                        ],
                        onChanged: (v) => setState(() => kind = v!)),
                    if (kind != 'income')
                      TextField(
                          controller: quantity,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'Quantidade',
                              helperText:
                                  'Até 6 casas decimais. Sem separador de milhar.')),
                    TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                            labelText: kind == 'opening'
                                ? 'Custo total de aquisição (R\$)'
                                : 'Valor total da operação (R\$)',
                            helperText: kind == 'sell'
                                ? 'Valor líquido recebido, após taxas.'
                                : 'Na compra, inclua as taxas no custo.')),
                    TextButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                              context: context,
                              initialDate: date,
                              firstDate: DateTime(1970),
                              lastDate: DateTime.now());
                          if (picked != null && mounted)
                            setState(() => date = picked);
                        },
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(ptDate(date))),
                    if (assetClass == 'Renda fixa' && widget.position == null)
                      const Text(
                          'Você pode representar um título como 1 unidade e atualizar seu valor manualmente pelo extrato. Não estimamos juros futuros.'),
                    const SizedBox(height: 8),
                    const Text(
                        'Registro de acompanhamento. Não movimenta contas bancárias.'),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ]))),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: busy ? null : save,
                child: Text(busy ? 'Salvando…' : 'Salvar'))
          ]);
}

class _PriceDialog extends StatefulWidget {
  final InvestmentPosition position;
  const _PriceDialog({required this.position});
  @override
  State<_PriceDialog> createState() => _PriceDialogState();
}

class _PriceDialogState extends State<_PriceDialog> {
  final price = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Preço unitário de hoje'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                  controller: price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Preço por unidade (R\$)', errorText: error)),
              const SizedBox(height: 12),
              const Text(
                  'Atualiza somente a avaliação da posição. Não gera rendimento recebido nem altera o custo de aquisição.')
            ]),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        final value = parseMoney(price.text);
                        if (value == null || value < 0) {
                          setState(() => error = 'Informe um preço válido.');
                          return;
                        }
                        setState(() => busy = true);
                        try {
                          await InvestmentRepository().price(
                              widget.position.investment.id,
                              (value * investmentScale).round(),
                              DateTime.now(),
                              'manual');
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (mounted)
                            setState(() =>
                                error = 'Não foi possível salvar o preço.');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Salvar preço'))
          ]);
}

class _QuoteSettingsDialog extends StatefulWidget {
  const _QuoteSettingsDialog();
  @override
  State<_QuoteSettingsDialog> createState() => _QuoteSettingsDialogState();
}

class _QuoteSettingsDialogState extends State<_QuoteSettingsDialog> {
  final token = TextEditingController();
  bool enabled = false, busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final on = await InvestmentQuoteSettings.enabled();
      final key = await InvestmentQuoteSettings.token();
      if (mounted)
        setState(() {
          enabled = on;
          token.text = key ?? '';
          busy = false;
        });
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Não foi possível acessar o armazenamento seguro. Feche e tente novamente.');
    }
  }

  @override
  void dispose() {
    token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Cotações opcionais'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text(
                    'A brapi recebe somente os códigos consultados e os dados técnicos da conexão, como IP. Quantidades, valores aplicados e histórico não são enviados. Sem vínculo com sua corretora.'),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Consultar ao abrir a carteira'),
                    subtitle: const Text(
                        'No máximo a cada 15 minutos. Sem atualização em segundo plano.'),
                    value: enabled,
                    onChanged:
                        busy ? null : (v) => setState(() => enabled = v)),
                TextField(
                    controller: token,
                    enabled: !busy,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                        labelText: 'Chave pessoal brapi (opcional)',
                        helperText:
                            'Guardada no armazenamento seguro; fora do backup.')),
                const SizedBox(height: 12),
                const Text(
                    'Sem chave: PETR4, VALE3, ITUB4 e MGLU3 para teste. Outros códigos dependem do seu plano. FIIs, ETFs, renda fixa e cripto usam preço manual nesta versão. Não é cotação garantida em tempo real.'),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          await InvestmentQuoteSettings.configure(
                              enabled: enabled, token: token.text);
                          if (context.mounted) Navigator.pop(context);
                        } catch (_) {
                          if (mounted)
                            setState(() => error =
                                'Falha ao salvar a configuração segura.');
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: const Text('Salvar'))
          ]);
}
