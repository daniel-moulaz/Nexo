import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../investments/investment_models.dart';
import 'analysis_widgets.dart';

class PortfolioCharts extends StatefulWidget {
  final List<InvestmentPosition> positions;
  final ValueChanged<String> onAsset;
  const PortfolioCharts(
      {super.key, required this.positions, required this.onAsset});
  @override
  State<PortfolioCharts> createState() => _PortfolioChartsState();
}

class _PortfolioChartsState extends State<PortfolioCharts> {
  String _mode = 'Distribuição';
  String _label(InvestmentPosition p) =>
      p.investment.ticker.isEmpty ? p.investment.name : p.investment.ticker;
  String _money(int cents) =>
      NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(cents / 100);
  @override
  Widget build(BuildContext context) {
    final private = context.watch<AppProvider>().settings.hideBalance;
    return AnalysisCard(
        title: 'Carteira em gráficos',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 8, children: [
              for (final mode in ['Distribuição', 'Resultado', 'Proventos'])
                ChoiceChip(
                    label: Text(mode),
                    selected: mode == _mode,
                    onSelected: (_) => setState(() => _mode = mode))
            ]),
            const SizedBox(height: 16),
            if (private)
              const Text('Gráficos ocultos no modo privado.')
            else if (_mode == 'Distribuição')
              _allocation(context)
            else if (_mode == 'Resultado')
              _results(context)
            else
              _income(context),
          ],
        ));
  }

  Widget _allocation(BuildContext context) {
    final positions = widget.positions.where((p) => p.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = positions.fold(0, (v, p) => v + p.value);
    if (total == 0)
      return const Text(
          'A distribuição aparece quando houver posições com valor positivo.');
    final slices = <({String label, int value, String? id})>[
      for (final p in positions.take(6))
        (label: _label(p), value: p.value, id: p.investment.id),
      if (positions.length > 6)
        (
          label: 'Outros ${positions.length - 6} ativos',
          value: positions.skip(6).fold(0, (v, p) => v + p.value),
          id: null
        ),
    ];
    const colors = [
      Color(0xff00a878),
      Color(0xff52a9ef),
      Color(0xffa18af5),
      Color(0xfff1b64a),
      Color(0xffec8db5),
      Color(0xff64c9c3),
      Color(0xff89959e)
    ];
    final chart = SizedBox(
        height: 170,
        child: Semantics(
            label:
                'Distribuição pelo valor atual dos ativos. Detalhes na lista.',
            child: ExcludeSemantics(
                child: PieChart(PieChartData(
              centerSpaceRadius: 48,
              sectionsSpace: 3,
              pieTouchData: PieTouchData(touchCallback: (event, response) {
                final index =
                    response?.touchedSection?.touchedSectionIndex ?? -1;
                if (event is FlTapUpEvent &&
                    index >= 0 &&
                    index < slices.length &&
                    slices[index].id != null) widget.onAsset(slices[index].id!);
              }),
              sections: [
                for (var i = 0; i < slices.length; i++)
                  PieChartSectionData(
                      value: slices[i].value.toDouble(),
                      color: colors[i],
                      radius: 28,
                      showTitle: false)
              ],
            )))));
    final legend = Column(children: [
      for (var i = 0; i < slices.length; i++)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: CircleAvatar(radius: 5, backgroundColor: colors[i]),
          title: Text(slices[i].label,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
              '${_money(slices[i].value)} · ${NumberFormat('0.0', 'pt_BR').format(slices[i].value * 100 / total)}%'),
          trailing:
              slices[i].id == null ? null : const Icon(Icons.chevron_right),
          onTap:
              slices[i].id == null ? null : () => widget.onAsset(slices[i].id!),
        )
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Onde seu dinheiro está investido'),
      LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 600
              ? Row(children: [
                  SizedBox(width: 240, child: chart),
                  Expanded(child: legend)
                ])
              : Column(children: [chart, legend])),
    ]);
  }

  Widget _results(BuildContext context) {
    final positions = widget.positions.where((p) => p.quantity > 0).toList()
      ..sort((a, b) => b.unrealized.abs().compareTo(a.unrealized.abs()));
    final shown = positions.take(8).toList();
    if (shown.isEmpty) return const Text('Sem posições abertas para comparar.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Ganho ou perda na posição atual · em reais'),
      const SizedBox(height: 16),
      _bars(context, [for (final p in shown) p.unrealized],
          [for (final p in shown) _label(p)],
          onTap: (i) => widget.onAsset(shown[i].investment.id)),
      for (final p in shown)
        ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(_label(p)),
            trailing: Text(_money(p.unrealized),
                style: TextStyle(
                    color: p.unrealized < 0
                        ? Theme.of(context).colorScheme.error
                        : const Color(0xff008f64))),
            onTap: () => widget.onAsset(p.investment.id)),
      Text(
          '${positions.length > 8 ? 'Oito maiores variações em valor absoluto. ' : ''}Valor atual menos custo restante. Vendas e proventos ficam separados.'),
    ]);
  }

  Widget _income(BuildContext context) {
    final now = DateTime.now();
    final months = [
      for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)
    ];
    final values = [
      for (final month in months)
        widget.positions
            .expand((p) => p.operations)
            .where((o) =>
                o.kind == 'income' &&
                !o.date.isAfter(now) &&
                o.date.toLocal().year == month.year &&
                o.date.toLocal().month == month.month)
            .fold(0, (v, o) => v + o.cents)
    ];
    if (values.every((v) => v == 0))
      return const Text(
          'Nenhum provento registrado nos últimos seis meses. Registre um recebimento no ativo para acompanhar aqui.');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Proventos recebidos · últimos seis meses'),
      const SizedBox(height: 16),
      _bars(context, values,
          [for (final m in months) DateFormat('MMM', 'pt_BR').format(m)]),
      const SizedBox(height: 8),
      Wrap(spacing: 16, runSpacing: 8, children: [
        for (var i = 0; i < months.length; i++)
          Text(
              '${DateFormat('MMM', 'pt_BR').format(months[i])}: ${_money(values[i])}'),
      ]),
      Text('Total registrado: ${_money(values.fold(0, (a, b) => a + b))}'),
      const Text(
          'Somente recebimentos que você registrou. Não é previsão de dividendos.'),
    ]);
  }

  Widget _bars(BuildContext context, List<int> values, List<String> labels,
      {ValueChanged<int>? onTap}) {
    final max =
        values.fold<double>(1, (v, n) => math.max(v, n.abs() / 100)) * 1.15;
    return SizedBox(
        height: 190,
        child: BarChart(BarChartData(
          minY: values.any((v) => v < 0) ? -max : 0,
          maxY: max,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          extraLinesData: ExtraLinesData(horizontalLines: [
            HorizontalLine(
                y: 0, color: Theme.of(context).dividerColor, strokeWidth: 1)
          ]),
          barTouchData: BarTouchData(
              touchCallback: (event, response) {
                final i = response?.spot?.touchedBarGroupIndex;
                if (event is FlTapUpEvent &&
                    i != null &&
                    i >= 0 &&
                    i < values.length) onTap?.call(i);
              },
              touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                          '${labels[groupIndex]}\n${_money(values[groupIndex])}',
                          const TextStyle(color: Colors.white)))),
          barGroups: [
            for (var i = 0; i < values.length; i++)
              BarChartGroupData(x: i, barRods: [
                BarChartRodData(
                    toY: values[i] / 100,
                    width: values.length > 6 ? 16 : 24,
                    color: values[i] < 0
                        ? Theme.of(context).colorScheme.error
                        : const Color(0xff00a878),
                    borderRadius: BorderRadius.circular(4))
              ])
          ],
        )));
  }
}
