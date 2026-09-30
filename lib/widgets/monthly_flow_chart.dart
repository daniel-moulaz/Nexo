import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../services/financial_analysis.dart';
import '../screens/analysis_screen.dart';
import 'analysis_widgets.dart';

class MonthlyFlowChart extends StatelessWidget {
  final AppProvider app;
  const MonthlyFlowChart({super.key, required this.app});
  @override
  Widget build(BuildContext context) {
    if (app.settings.hideBalance)
      return const Text('Gráfico oculto no modo privado.');
    final now = DateTime.now();
    final months =
        List.generate(6, (i) => DateTime(now.year, now.month - 5 + i));
    final data = months
        .map((m) => analyzePeriod(app, FinancialAnalysis.month(m, now)))
        .toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Azul: receitas • laranja: despesas. Mês atual parcial.'),
      const SizedBox(height: 12),
      SizedBox(
          height: 165,
          child: BarChart(BarChartData(
            borderData: FlBorderData(show: false),
            gridData: const FlGridData(show: false),
            titlesData: FlTitlesData(
              topTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles:
                  const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) => Text(DateFormat('MM/yy')
                          .format(months[value.toInt().clamp(0, 5)])))),
            ),
            barTouchData: BarTouchData(touchCallback: (event, response) {
              final index = response?.spot?.touchedBarGroupIndex;
              if (event is FlTapUpEvent && index != null)
                openAnalysisEntries(context, data[index].realized,
                    DateFormat('MM/yyyy').format(months[index]));
            }),
            barGroups: [
              for (var i = 0; i < 6; i++)
                BarChartGroupData(x: i, barRods: [
                  BarChartRodData(
                      toY: data[i].income, color: Colors.blue, width: 12),
                  BarChartRodData(
                      toY: data[i].expense,
                      color: Colors.deepOrange,
                      width: 12),
                ])
            ],
          ))),
      const SizedBox(height: 8),
      for (var i = 0; i < 6; i++)
        InkWell(
          onTap: () => openAnalysisEntries(context, data[i].realized,
              DateFormat('MM/yyyy').format(months[i])),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(child: Text(DateFormat('MM/yyyy').format(months[i]))),
                Text(
                    '${analysisMoney(app, data[i].income)} / ${analysisMoney(app, data[i].expense)}'),
              ])),
        ),
    ]);
  }
}
