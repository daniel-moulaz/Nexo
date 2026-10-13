import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../services/cash_timeline.dart';
import '../utils/finance_input.dart';

class CashTimelineChart extends StatelessWidget {
  final CashTimeline timeline;
  final String Function(double) money;
  const CashTimelineChart(
      {super.key, required this.timeline, required this.money});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final low = timeline.lowest.balance;
    final high = timeline.points.map((p) => p.balance).reduce(math.max);
    final padding =
        math.max((high - low).abs() * .18, math.max(high.abs() * .03, 1));
    final color = low < 0 ? cs.error : cs.primary;
    return Column(children: [
      Semantics(
          label:
              'Saldo diário previsto. Agora ${money(timeline.points.first.balance)}. Menor saldo ${money(low)}. Final ${money(timeline.points.last.balance)}.',
          child: ExcludeSemantics(
              child: SizedBox(
                  height: 122,
                  child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: (timeline.points.length - 1).toDouble(),
                        minY: low - padding,
                        maxY: high + padding,
                        clipData: const FlClipData.all(),
                        borderData: FlBorderData(show: false),
                        titlesData: const FlTitlesData(show: false),
                        gridData: const FlGridData(show: false),
                        extraLinesData: ExtraLinesData(horizontalLines: [
                          if (low < 0 && high >= 0)
                            HorizontalLine(
                                y: 0,
                                color: cs.error.withValues(alpha: .5),
                                strokeWidth: 1,
                                dashArray: [4, 4]),
                        ]),
                        lineTouchData: LineTouchData(
                            touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) => cs.inverseSurface,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItems: (spots) => spots.map((spot) {
                            final index = spot.x
                                .round()
                                .clamp(0, timeline.points.length - 1);
                            final point = timeline.points[index];
                            return LineTooltipItem(
                                '${index == 0 ? 'Agora' : ptDate(point.date)}\n${money(point.balance)}',
                                TextStyle(color: cs.onInverseSurface));
                          }).toList(),
                        )),
                        lineBarsData: [
                          LineChartBarData(
                            spots: [
                              for (var i = 0; i < timeline.points.length; i++)
                                FlSpot(i.toDouble(), timeline.points[i].balance)
                            ],
                            isCurved: false,
                            isStepLineChart: true,
                            barWidth: 3,
                            color: color,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(
                                show: true,
                                color: color.withValues(alpha: .09)),
                          )
                        ],
                      ),
                      duration: Duration.zero)))),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Agora'),
        Text(ptShortDate(timeline.points.last.date))
      ]),
    ]);
  }
}
