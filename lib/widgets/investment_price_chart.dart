import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../investments/investment_history.dart';
import '../investments/investment_quotes.dart';
import 'analysis_widgets.dart';

class InvestmentPriceChart extends StatefulWidget {
  final String ticker;
  const InvestmentPriceChart({super.key, required this.ticker});
  @override
  State<InvestmentPriceChart> createState() => _InvestmentPriceChartState();
}

class _InvestmentPriceChartState extends State<InvestmentPriceChart> {
  PriceHistory? _history;
  bool _loading = true;
  int _days = 90;
  String? _message;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final cache = await InvestmentHistory.cached(widget.ticker);
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
      if (!await InvestmentHistory.claim(widget.ticker)) {
        _message = 'Nova consulta de histórico disponível após 30 minutos.';
        return;
      }
      final token = await InvestmentQuoteSettings.token();
      final history =
          await InvestmentHistory().fetch(widget.ticker, token: token);
      await InvestmentHistory.save(widget.ticker, history);
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
    final money = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final change = points.length < 2
        ? null
        : (points.last.price / points.first.price - 1) * 100;
    final color = change == null || change >= 0
        ? const Color(0xff008f64)
        : Theme.of(context).colorScheme.error;
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
                        ?.copyWith(color: color, fontWeight: FontWeight.w800)),
                const Text(
                    'Fechamento ajustado · variação entre os pontos exibidos'),
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
                          lineTouchData: LineTouchData(
                              touchTooltipData: LineTouchTooltipData(
                                  getTooltipItems: (spots) => spots.map((s) {
                                        final p = points[s.spotIndex];
                                        return LineTooltipItem(
                                            '${DateFormat('dd/MM/yyyy').format(p.date.toLocal())}\n${money.format(p.price)}',
                                            const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold));
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
                    'brapi · consultado em ${DateFormat('dd/MM HH:mm').format(_history!.fetchedAt.toLocal())}',
                    style: Theme.of(context).textTheme.bodySmall),
              ] else if (!_loading)
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                        'Sem histórico suficiente para desenhar o gráfico.')),
              if (_message != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_message!)),
              const SizedBox(height: 8),
              const Text(
                  'Preço ajustado por eventos conforme a fonte. Não é o rendimento da sua carteira nem o preço exato de compra. Somente pregões informados pela fonte.',
                  style: TextStyle(fontSize: 12)),
            ],
          ],
        ));
  }
}
