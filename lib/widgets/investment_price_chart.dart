import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../investments/investment_history.dart';
import '../investments/investment_quotes.dart';
import '../investments/foreign_quotes.dart';
import 'analysis_widgets.dart';
import '../theme/nexo_tokens.dart';

class InvestmentPriceChart extends StatefulWidget {
  final String ticker;

  /// A US asset: closes kept by the Nexo server, in dollars.
  final bool foreign;

  /// The average price paid, in the asset's currency: a reference line.
  final double? averageCost;
  const InvestmentPriceChart(
      {super.key,
      required this.ticker,
      this.foreign = false,
      this.averageCost});
  @override
  State<InvestmentPriceChart> createState() => _InvestmentPriceChartState();
}

class _InvestmentPriceChartState extends State<InvestmentPriceChart> {
  PriceHistory? _history;
  bool _loading = true;
  int _days = 90;
  String? _message;

  /// US closes are cached apart: the same ticker could exist on both sides.
  String get _key => widget.foreign ? 'us_${widget.ticker}' : widget.ticker;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final cache = await InvestmentHistory.cached(_key);
      if (mounted) setState(() => _history = cache);
      if (!mounted || context.read<AppProvider>().settings.hideBalance) return;
      if (!await InvestmentQuoteSettings.enabled()) {
        _message =
            'Ative as cotações nas configurações de Investimentos para consultar o histórico.';
        return;
      }
      if (!force &&
          cache != null &&
          DateTime.now().difference(cache.fetchedAt) <
              const Duration(hours: 12)) return;
      if (!widget.foreign && !await InvestmentHistory.claim(widget.ticker)) {
        _message = 'Nova consulta de histórico disponível após 30 minutos.';
        return;
      }
      final PriceHistory history;
      if (widget.foreign) {
        final source = SupabaseForeignQuotes.instance;
        if (source is! ForeignHistorySource) {
          _message = 'Histórico dos EUA disponível com a conta conectada.';
          return;
        }
        history = await (source as ForeignHistorySource).history(widget.ticker);
      } else {
        final token = await InvestmentQuoteSettings.token();
        history = await InvestmentHistory().fetch(widget.ticker, token: token);
      }
      await InvestmentHistory.save(_key, history);
      if (mounted)
        setState(() {
          _history = history;
          _message = null;
        });
    } on QuoteFailure catch (e) {
      _message = e.message;
    } catch (_) {
      _message =
          'Não foi possível carregar o histórico. Sua carteira continua disponível.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final private = context.watch<AppProvider>().settings.hideBalance;
    final points = _history?.window(_days) ?? <PricePoint>[];
    final money = NumberFormat.currency(
        locale: 'pt_BR', symbol: widget.foreign ? 'US\$' : 'R\$');
    final cost = widget.averageCost;
    final change = points.length < 2
        ? null
        : (points.last.price / points.first.price - 1) * 100;
    final color = change == null || change >= 0
        ? NexoTones.income(context)
        : NexoTones.expense(context);
    return AnalysisCard(
        title: 'Evolução do ativo',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (private)
              const Text('Gráfico oculto no modo privado.')
            else ...[
              Wrap(spacing: 8, children: [
                for (final d in [30, 90])
                  ChoiceChip(
                      label: Text(d == 30 ? '1 mês' : '3 meses'),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d)),
                IconButton(
                    tooltip: 'Atualizar histórico',
                    onPressed: _loading ? null : () => _load(force: true),
                    icon: const Icon(Icons.refresh)),
              ]),
              if (_loading) const LinearProgressIndicator(),
              if (points.length >= 2) ...[
                const SizedBox(height: 12),
                Text(
                    '${money.format(points.last.price)} · ${change! >= 0 ? '+' : ''}${NumberFormat('0.00', 'pt_BR').format(change)}%',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w600)),
                Text(widget.foreign
                    ? 'Fechamento de cada dia · variação entre os pontos exibidos'
                    : 'Fechamento ajustado · variação entre os pontos exibidos'),
                if (cost != null && cost > 0)
                  Text(
                      'Linha tracejada: seu preço médio, ${money.format(cost)}',
                      style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 20),
                SizedBox(
                    height: 180,
                    child: Semantics(
                        label:
                            'Histórico de preço ajustado de ${widget.ticker}. Toque para consultar data e preço.',
                        child: LineChart(LineChartData(
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          // Keeps the average price in view with the prices.
                          minY: cost != null && cost > 0
                              ? [cost, ...points.map((p) => p.price)]
                                      .reduce((a, b) => a < b ? a : b) *
                                  0.97
                              : null,
                          maxY: cost != null && cost > 0
                              ? [cost, ...points.map((p) => p.price)]
                                      .reduce((a, b) => a > b ? a : b) *
                                  1.03
                              : null,
                          extraLinesData: ExtraLinesData(horizontalLines: [
                            if (cost != null && cost > 0)
                              HorizontalLine(
                                  y: cost,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  strokeWidth: 1.5,
                                  dashArray: [6, 4]),
                          ]),
                          lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                  getTooltipColor: (_) =>
                                      NexoChart.tooltip(context),
                                  getTooltipItems: (spots) => spots.map((s) {
                                        final p = points[s.spotIndex];
                                        return LineTooltipItem(
                                            '${DateFormat('dd/MM/yyyy').format(p.date.toLocal())}\n${money.format(p.price)}',
                                            NexoChart.tooltipText(context));
                                      }).toList())),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < points.length; i++)
                                  FlSpot(
                                      points[i]
                                          .date
                                          .millisecondsSinceEpoch
                                          .toDouble(),
                                      points[i].price)
                              ],
                              isCurved: false,
                              color: color,
                              barWidth: 2.5,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                  show: true,
                                  color: color.withValues(alpha: .10)),
                            )
                          ],
                        )))),
                const SizedBox(height: 8),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(DateFormat('dd/MM/yy')
                          .format(points.first.date.toLocal())),
                      Text(DateFormat('dd/MM/yy')
                          .format(points.last.date.toLocal())),
                    ]),
                const SizedBox(height: 8),
                Text(
                    '${widget.foreign ? 'Fechamentos guardados pelo Nexo' : 'brapi'} · consultado em ${DateFormat('dd/MM HH:mm').format(_history!.fetchedAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall),
              ] else if (!_loading)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(widget.foreign
                        ? 'O histórico começa agora: o Nexo guarda o fechamento de cada dia em que a cotação é consultada. Com dois dias já aparece a linha; em algumas semanas, a tendência.'
                        : 'Sem histórico suficiente para desenhar o gráfico.')),
              if (_message != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message!)),
              const SizedBox(height: 8),
              Text(
                  widget.foreign
                      ? 'Preço em dólar, sem ajuste de desdobramentos. Não inclui o câmbio: o resultado em reais está acima, em "Em dólar e em reais".'
                      : 'Preço ajustado por eventos conforme a fonte. Não é o rendimento da sua carteira nem o preço exato de compra. Somente pregões informados pela fonte.',
                  style: const TextStyle(fontSize: 12)),
            ],
          ],
        ));
  }
}
