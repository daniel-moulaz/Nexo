import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../providers/app_provider.dart';
import '../services/financial_analysis.dart';
import '../theme/app_theme.dart';

String analysisMoney(AppProvider app, double value) => app.settings.hideBalance
    ? '••••'
    : formatAmount(value, app.settings.currency);

class AnalysisCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  const AnalysisCard(
      {super.key, required this.title, required this.child, this.action});
  @override
  Widget build(BuildContext context) => Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold))),
              if (action != null) action!
            ]),
            const SizedBox(height: 12),
            child
          ])));
}

class AnalysisMetrics extends StatelessWidget {
  final List<(String, String)> values;
  const AnalysisMetrics({super.key, required this.values});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 700 ? values.length : 2;
        return Wrap(spacing: 12, runSpacing: 16, children: [
          for (final v in values)
            SizedBox(
                width: (c.maxWidth - 12 * (columns - 1)) / columns,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(v.$1, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      Text(v.$2,
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700))
                    ]))
        ]);
      });
}

class CategoryBreakdown extends StatelessWidget {
  final AppProvider app;
  final FinancialAnalysis data;
  final void Function(String) onCategory;
  final bool compact;
  const CategoryBreakdown(
      {super.key,
      required this.app,
      required this.data,
      required this.onCategory,
      this.compact = false});
  @override
  Widget build(BuildContext context) {
    if (data.expense == 0)
      return const Text(
          'Sem despesas realizadas neste período. Registre uma despesa para começar a análise.');
    if (app.settings.hideBalance)
      return const Text('Valores e distribuição ocultos no modo privado.');
    final all = data.topCategories;
    final shown = compact ? all.take(3).toList() : all;
    Color color(String id) =>
        Color(app.categoryById(id)?.colorValue ?? 0xFF607D8B);
    return Column(children: [
      SizedBox(
          height: compact ? 140 : 190,
          child: Semantics(
              label:
                  'Distribuição das despesas por categoria. Detalhes na lista abaixo.',
              child: ExcludeSemantics(
                  child: PieChart(PieChartData(
                      centerSpaceRadius: compact ? 38 : 50,
                      sectionsSpace: 3,
                      pieTouchData:
                          PieTouchData(touchCallback: (event, response) {
                        final index =
                            response?.touchedSection?.touchedSectionIndex ?? -1;
                        if (event is FlTapUpEvent &&
                            index >= 0 &&
                            index < all.length) onCategory(all[index].key);
                      }),
                      sections: [
                    for (final e in all)
                      PieChartSectionData(
                          value: e.value,
                          color: color(e.key),
                          radius: compact ? 26 : 36,
                          showTitle: false)
                  ]))))),
      for (final e in shown)
        ListTile(
            contentPadding: EdgeInsets.zero,
            minLeadingWidth: 12,
            leading: CircleAvatar(radius: 6, backgroundColor: color(e.key)),
            title: Text(app.categoryById(e.key)?.name ?? 'Sem categoria'),
            subtitle: Text(
                '${analysisMoney(app, e.value)} • ${(e.value / data.expense * 100).toStringAsFixed(1)}%'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onCategory(e.key)),
      if (compact && all.length > 3)
        Text('Mais ${all.length - 3} categorias em Análises'),
    ]);
  }
}
