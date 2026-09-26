import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/finance_rules.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';

class FinancialPlanningScreen extends StatefulWidget {
  const FinancialPlanningScreen({super.key});

  @override
  State<FinancialPlanningScreen> createState() => _FinancialPlanningScreenState();
}

class _FinancialPlanningScreenState extends State<FinancialPlanningScreen> {
  Future<Map<String, TransactionMetadata>>? _metadataFuture;
  int _lastCount = -1;

  Future<Map<String, TransactionMetadata>> _metadata(AppProvider app) {
    if (_metadataFuture == null || _lastCount != app.transactions.length) {
      _lastCount = app.transactions.length;
      _metadataFuture = TransactionMetadataService.instance
          .getForMany(app.transactions.map((e) => e.id));
    }
    return _metadataFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return FutureBuilder<Map<String, TransactionMetadata>>(
      future: _metadata(app),
      builder: (context, snapshot) {
        return _PlanningBody(
          app: app,
          metadata: snapshot.data ?? const <String, TransactionMetadata>{},
        );
      },
    );
  }
}

class _PlanningBody extends StatelessWidget {
  final AppProvider app;
  final Map<String, TransactionMetadata> metadata;

  const _PlanningBody({required this.app, required this.metadata});

  String _currencyFor(AppTransaction tx) {
    if (tx.currency.isNotEmpty) return tx.currency;
    return app.accountById(tx.accountId)?.currency ?? app.settings.currency;
  }

  double _mainAmount(AppTransaction tx) =>
      app.convertToMain(tx.amount, _currencyFor(tx));

  bool _inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;

  double _expenseForMonth(DateTime month) {
    double total = 0;
    for (final tx in app.transactions) {
      if (tx.type != 'expense' || !_inMonth(tx.date, month)) continue;
      final meta = metadata[tx.id];
      if (FinanceRules.isNeutral(tx, meta)) continue;
      total += _mainAmount(tx);
    }
    return total;
  }

  double _incomeForMonth(DateTime month) {
    double total = 0;
    for (final tx in app.transactions) {
      if (tx.type != 'income' || !_inMonth(tx.date, month)) continue;
      final meta = metadata[tx.id];
      if (FinanceRules.isNeutral(tx, meta)) continue;
      total += _mainAmount(tx);
    }
    return total;
  }

  DateTime _advance(DateTime date, RecurringPayment r) {
    switch (r.freqUnit) {
      case 'days':
        return date.add(Duration(days: r.freqVal));
      case 'weeks':
        return date.add(Duration(days: r.freqVal * 7));
      case 'years':
        return DateTime(date.year + r.freqVal, date.month, date.day);
      case 'months':
      default:
        final m = date.month + r.freqVal;
        final y = date.year + (m - 1) ~/ 12;
        final month = ((m - 1) % 12) + 1;
        final day = date.day.clamp(1, DateTime(y, month + 1, 0).day);
        return DateTime(y, month, day);
    }
  }

  List<_ForecastItem> _forecast(DateTime now, DateTime horizon) {
    final result = <_ForecastItem>[];
    for (final r in app.recurring) {
      var next = r.nextDate;
      var guard = 0;
      while (next.isBefore(now) && guard < 120) {
        next = _advance(next, r);
        guard++;
      }
      while (!next.isAfter(horizon) && guard < 180) {
        if (r.endDate == null || !next.isAfter(r.endDate!)) {
          result.add(_ForecastItem(
            date: next,
            name: r.name,
            amount: app.convertToMain(
              r.amount,
              app.accountById(r.accountId)?.currency ?? app.settings.currency,
            ),
            type: r.paymentType,
            recurringType: r.recurringType,
          ));
        }
        next = _advance(next, r);
        guard++;
      }
    }
    result.sort((a, b) => a.date.compareTo(b.date));
    return result;
  }

  double _monthlyEquivalent(RecurringPayment r) {
    final amount = app.convertToMain(
      r.amount,
      app.accountById(r.accountId)?.currency ?? app.settings.currency,
    );
    switch (r.freqUnit) {
      case 'days':
        return amount * (30 / r.freqVal);
      case 'weeks':
        return amount * (4.345 / r.freqVal);
      case 'years':
        return amount / (12 * r.freqVal);
      case 'months':
      default:
        return amount / r.freqVal;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final previousMonth = DateTime(now.year, now.month - 1);
    final currentExpense = _expenseForMonth(currentMonth);
    final previousExpense = _expenseForMonth(previousMonth);
    final currentIncome = _incomeForMonth(currentMonth);
    final monthDelta = previousExpense <= 0
        ? null
        : ((currentExpense - previousExpense) / previousExpense) * 100;

    final forecast = _forecast(now, now.add(const Duration(days: 30)));
    final expectedIncome = forecast
        .where((e) => e.type == 'income')
        .fold<double>(0, (sum, e) => sum + e.amount);
    final expectedExpense = forecast
        .where((e) => e.type == 'expense')
        .fold<double>(0, (sum, e) => sum + e.amount);
    final netForecast = expectedIncome - expectedExpense;

    final subscriptions = app.recurring
        .where((r) => r.paymentType == 'expense' && r.recurringType == 'subscription')
        .toList();
    final subscriptionsMonthly = subscriptions.fold<double>(
      0,
      (sum, r) => sum + _monthlyEquivalent(r),
    );

    final categoryTotals = <String, double>{};
    for (final tx in app.transactions) {
      if (tx.type != 'expense' || !_inMonth(tx.date, currentMonth)) continue;
      if (FinanceRules.isNeutral(tx, metadata[tx.id])) continue;
      categoryTotals.update(
        tx.categoryId,
        (value) => value + _mainAmount(tx),
        ifAbsent: () => _mainAmount(tx),
      );
    }
    MapEntry<String, double>? topCategory;
    for (final entry in categoryTotals.entries) {
      if (topCategory == null || entry.value > topCategory.value) {
        topCategory = entry;
      }
    }

    final riskyBudgets = <_BudgetRisk>[];
    for (final budget in app.budgets) {
      if (budget.amount <= 0) continue;
      final spent = app.budgetSpent(budget);
      final ratio = spent / budget.amount;
      if (ratio >= .75) {
        riskyBudgets.add(_BudgetRisk(
          budget: budget,
          ratio: ratio,
          spent: spent,
        ));
      }
    }
    riskyBudgets.sort((a, b) => b.ratio.compareTo(a.ratio));

    final recentMonths = List.generate(
      3,
      (i) => DateTime(now.year, now.month - i - 1),
    );
    final historical = recentMonths.map(_expenseForMonth).where((v) => v > 0).toList();
    final averageExpense = historical.isEmpty
        ? currentExpense
        : historical.reduce((a, b) => a + b) / historical.length;
    final reserveValue = app.accounts
            .where((a) => a.type == 'savings' && !a.excludeFromTotal)
            .fold<double>(
              0,
              (sum, a) => sum + app.convertToMain(a.balance, a.currency),
            ) +
        app.totalSaved;
    final reserveMonths = averageExpense > 0 ? reserveValue / averageExpense : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Planejamento',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: .58),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Próximos 30 dias',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  netForecast >= 0
                      ? 'Fluxo previsto positivo'
                      : 'Saídas previstas acima das entradas',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  formatAmount(netForecast, app.settings.currency),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: netForecast < 0 ? cs.error : null,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _Metric(
                        label: 'Entradas previstas',
                        value: formatAmount(expectedIncome, app.settings.currency),
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Metric(
                        label: 'Saídas previstas',
                        value: formatAmount(expectedExpense, app.settings.currency),
                        icon: Icons.north_east_rounded,
                        danger: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Inteligência do mês'),
          const SizedBox(height: 8),
          _InsightTile(
            icon: monthDelta == null || monthDelta <= 0
                ? Icons.trending_down_rounded
                : Icons.trending_up_rounded,
            title: 'Comparação com o mês passado',
            value: monthDelta == null
                ? 'Ainda sem base suficiente'
                : '${monthDelta >= 0 ? '+' : ''}${monthDelta.toStringAsFixed(1).replaceAll('.', ',')}%',
            subtitle: '${formatAmount(currentExpense, app.settings.currency)} gastos neste mês',
            danger: monthDelta != null && monthDelta > 10,
          ),
          _InsightTile(
            icon: Icons.category_outlined,
            title: 'Categoria que mais pesa',
            value: topCategory == null
                ? 'Sem gastos categorizados'
                : (app.categoryById(topCategory.key)?.name ?? 'Outros'),
            subtitle: topCategory == null
                ? 'Comece registrando seus gastos'
                : formatAmount(topCategory.value, app.settings.currency),
          ),
          _InsightTile(
            icon: Icons.autorenew_rounded,
            title: 'Assinaturas',
            value: '${subscriptions.length} ativa${subscriptions.length == 1 ? '' : 's'}',
            subtitle: '${formatAmount(subscriptionsMonthly, app.settings.currency)}/mês estimado',
          ),
          _InsightTile(
            icon: Icons.savings_outlined,
            title: 'Reserva estimada',
            value: reserveMonths <= 0
                ? 'Sem cobertura calculável'
                : '${reserveMonths.toStringAsFixed(1).replaceAll('.', ',')} meses',
            subtitle: '${formatAmount(reserveValue, app.settings.currency)} em poupança/metas',
          ),
          if (currentIncome > 0)
            _InsightTile(
              icon: Icons.percent_rounded,
              title: 'Comprometimento da renda',
              value:
                  '${((currentExpense / currentIncome) * 100).toStringAsFixed(0)}%',
              subtitle: '${formatAmount(currentExpense, app.settings.currency)} de ${formatAmount(currentIncome, app.settings.currency)}',
              danger: currentExpense > currentIncome,
            ),
          if (riskyBudgets.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _SectionTitle('Orçamentos em atenção'),
            const SizedBox(height: 8),
            ...riskyBudgets.take(4).map((risk) {
              final category = app.categoryById(risk.budget.categoryId);
              final pct = (risk.ratio * 100).round();
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              category?.name ?? 'Orçamento',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            '$pct%',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: risk.ratio >= 1 ? cs.error : cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: risk.ratio.clamp(0.0, 1.0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${formatAmount(risk.spent, app.settings.currency)} de ${formatAmount(risk.budget.amount, app.settings.currency)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
          const SizedBox(height: 18),
          const _SectionTitle('Agenda financeira'),
          const SizedBox(height: 8),
          if (forecast.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Text(
                  'Nenhum pagamento recorrente previsto para os próximos 30 dias.',
                ),
              ),
            )
          else
            ...forecast.take(12).map(
              (item) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(item.type == 'income'
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${DateFormat('dd/MM/yyyy').format(item.date)}${item.recurringType == 'subscription' ? ' • assinatura' : ''}',
                  ),
                  trailing: Text(
                    '${item.type == 'income' ? '+' : '-'}${formatAmount(item.amount, app.settings.currency)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: item.type == 'income' ? Colors.green : cs.error,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: .72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: danger ? cs.error : cs.primary),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(label,
              maxLines: 2,
              style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String subtitle;
  final bool danger;

  const _InsightTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: (danger ? cs.error : cs.primary).withValues(alpha: .12),
          child: Icon(icon, color: danger ? cs.error : cs.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120),
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: danger ? cs.error : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      );
}

class _ForecastItem {
  final DateTime date;
  final String name;
  final double amount;
  final String type;
  final String recurringType;

  const _ForecastItem({
    required this.date,
    required this.name,
    required this.amount,
    required this.type,
    required this.recurringType,
  });
}

class _BudgetRisk {
  final Budget budget;
  final double ratio;
  final double spent;

  const _BudgetRisk({
    required this.budget,
    required this.ratio,
    required this.spent,
  });
}
