import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/app_provider.dart';
import '../services/month_review.dart';
import '../utils/finance_input.dart';
import '../widgets/analysis_widgets.dart';
import '../widgets/nexo_ui.dart';
import '../widgets/shared_widgets.dart' show CategoryDot;
import 'analysis_screen.dart';

const _weekdays = [
  'segunda',
  'terça',
  'quarta',
  'quinta',
  'sexta',
  'sábado',
  'domingo'
];

/// "Mês em revisão": the month told as highlights, compared with the month
/// before. Read-only.
class MonthReviewScreen extends StatefulWidget {
  const MonthReviewScreen({super.key, this.month});

  /// Defaults to the previous month (the one that just closed).
  final DateTime? month;
  @override
  State<MonthReviewScreen> createState() => _MonthReviewScreenState();
}

class _MonthReviewScreenState extends State<MonthReviewScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = widget.month ?? DateTime(now.year, now.month - 1);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final hidden = app.settings.hideBalance;
    String money(double v) => analysisMoney(app, v);
    final now = DateTime.now();
    final r = MonthReview.build(
        transactions: app.transactions,
        metadata: app.transactionMetadata,
        amount: (t) => app.convertToMain(
            t.amount,
            t.currency.isEmpty
                ? app.accountById(t.accountId)?.currency ??
                    app.settings.currency
                : t.currency),
        month: _month,
        now: now,
        budgetList: app.budgets);
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final canGoNext = !isCurrent;
    final change = r.change;
    final biggest = r.biggest;
    final weekday = r.busiestWeekday;
    final small = Theme.of(context).textTheme.bodySmall;

    Widget fact(IconData icon, String title, String value, {Color? color}) =>
        NexoCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: color ?? cs.primary),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: small),
                    Text(value,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ])),
            ]));

    return Scaffold(
      appBar: AppBar(title: const Text('Mês em revisão')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Row(children: [
            IconButton(
                tooltip: 'Mês anterior',
                onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1)),
                icon: const Icon(Icons.chevron_left)),
            Expanded(
                child: Text(
                    '${ptMonthYear(_month)}${isCurrent ? ' (até hoje)' : ''}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(
                tooltip: 'Próximo mês',
                onPressed: canGoNext
                    ? () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1))
                    : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
          const SizedBox(height: 8),
          NexoCard(
            gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [cs.primaryContainer, cs.tertiaryContainer]),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Você gastou',
                  style: TextStyle(
                      color: cs.onPrimaryContainer.withValues(alpha: .75))),
              FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(money(r.spent),
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: cs.onPrimaryContainer,
                          fontFeatures: NexoTones.figures))),
              if (!hidden)
                Text(
                    change == null
                        ? 'Sem gastos no mês anterior para comparar'
                        : change.abs() < 1
                            ? 'Igual ao mês anterior'
                            : '${change > 0 ? '▲' : '▼'} ${change.abs().toStringAsFixed(0)}% em relação a ${money(r.previousUsual)} no mês anterior',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: change == null || change.abs() < 1
                            ? cs.onPrimaryContainer
                            : change > 0
                                ? NexoTones.expense(context)
                                : NexoTones.income(context))),
              if (!hidden && r.comparesWithoutOneOffs)
                Text(
                    r.oneOff > 0
                        ? '${money(r.oneOff)} em gastos pontuais ficam fora da comparação.'
                        : 'Gastos pontuais do mês anterior ficam fora da comparação.',
                    style: TextStyle(
                        fontSize: 12,
                        color: cs.onPrimaryContainer.withValues(alpha: .75))),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: NexoStatPill(
                        label: 'Renda fixa', value: money(r.fixedIncome))),
                const SizedBox(width: 8),
                Expanded(
                    child: NexoStatPill(
                        label: 'Renda extra', value: money(r.extraIncome))),
                const SizedBox(width: 8),
                Expanded(
                    child: NexoStatPill(
                        label: 'Sobrou',
                        value: money(r.result),
                        valueColor: hidden
                            ? null
                            : r.result >= 0
                                ? NexoTones.income(context)
                                : NexoTones.expense(context))),
              ]),
            ]),
          ),
          const SizedBox(height: 16),
          if (r.spent > 0 && !hidden) ...[
            const NexoSectionTitle('Para onde foi',
                subtitle: 'As categorias que mais pesaram'),
            const SizedBox(height: 8),
            NexoCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  for (final (id, value, before) in r.topCategories())
                    ListTile(
                        leading: CategoryDot(
                            category: app.categoryById(id), size: 36),
                        title: Text(
                            app.categoryById(id)?.name ?? 'Sem categoria',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(before == 0
                            ? 'Não teve no mês anterior'
                            : '${value >= before ? '▲' : '▼'} ${money((value - before).abs())} em relação ao mês anterior'),
                        trailing: Text(money(value),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontFeatures: NexoTones.figures))),
                ])),
            const SizedBox(height: 16),
          ],
          const NexoSectionTitle('Destaques'),
          const SizedBox(height: 8),
          fact(Icons.spa_outlined, 'Dias sem gastar',
              '${r.quietDays} de ${r.daysCounted} dias'),
          const SizedBox(height: 8),
          if (biggest != null) ...[
            fact(
                Icons.north_east,
                'Maior gasto',
                hidden
                    ? 'Oculto no modo privado'
                    : '${biggest.description} · ${money(r.amountOf(biggest))}'),
            const SizedBox(height: 8),
          ],
          if (weekday != null) ...[
            fact(Icons.calendar_view_week_outlined,
                'Dia da semana que mais pesou', _weekdays[weekday - 1]),
            const SizedBox(height: 8),
          ],
          if (r.budgets.isNotEmpty)
            fact(Icons.pie_chart_outline, 'Orçamentos mensais cumpridos',
                '${r.budgetsKept} de ${r.budgets.length}',
                color: r.budgetsKept == r.budgets.length
                    ? NexoTones.income(context)
                    : NexoTones.warning(context)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          AnalysisScreen(initialMonth: _month, closing: true))),
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Ver fechamento detalhado')),
        ],
      ),
    );
  }
}
