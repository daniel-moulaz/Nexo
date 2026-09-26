import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/finance_rules.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import '../database/db_helper.dart';
import '../services/cash_forecast.dart';
import 'agenda_screen.dart';

class FinancialPlanningScreen extends StatelessWidget {
  const FinancialPlanningScreen({super.key});
  Future<List<Map<String, dynamic>>> _payments() async =>
      (await DBHelper.database).query('card_invoice_payments');
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return FutureBuilder<List<Map<String, dynamic>>>(
        future: _payments(),
        builder: (context, snapshot) {
          if (snapshot.hasError)
            return Scaffold(
                appBar: AppBar(title: const Text('Planejamento')),
                body: const Center(
                    child: Text(
                        'Não foi possível carregar. Reabra o planejamento.')));
          if (!snapshot.hasData)
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          return _PlanningBody(
              app: app,
              metadata: app.transactionMetadata,
              payments: snapshot.data!);
        });
  }
}

class _PlanningBody extends StatelessWidget {
  final AppProvider app;
  final Map<String, TransactionMetadata> metadata;
  final List<Map<String, dynamic>> payments;

  const _PlanningBody(
      {required this.app, required this.metadata, required this.payments});

  String _currencyFor(AppTransaction tx) {
    if (tx.currency.isNotEmpty) return tx.currency;
    return app.accountById(tx.accountId)?.currency ?? app.settings.currency;
  }

  double _mainAmount(AppTransaction tx) =>
      app.convertToMain(tx.amount, _currencyFor(tx));

  String _money(double value) {
    if (app.settings.hideBalance) return '••••••';
    return formatAmount(value, app.settings.currency);
  }

  bool _inMonth(DateTime date, DateTime month) =>
      date.year == month.year && date.month == month.month;

  double _expenseForMonth(DateTime month) {
    double total = 0;
    for (final tx in app.transactions) {
      if (tx.type != 'expense' || !_inMonth(tx.date, month)) continue;
      if (FinanceRules.isNeutral(tx, metadata[tx.id])) continue;
      total += _mainAmount(tx);
    }
    return total;
  }

  double _incomeForMonth(DateTime month) {
    double total = 0;
    for (final tx in app.transactions) {
      if (tx.type != 'income' || !_inMonth(tx.date, month)) continue;
      if (FinanceRules.isNeutral(tx, metadata[tx.id])) continue;
      total += _mainAmount(tx);
    }
    return total;
  }

  List<_ForecastItem> _forecast(DateTime now, DateTime horizon) {
    final result = CashForecast.calculate(
        now: now,
        until: horizon,
        accounts: app.accounts,
        transactions: app.transactions,
        recurring: app.recurring,
        metadata: metadata,
        invoicePayments: payments,
        convert: app.convertToMain);
    return result.events
        .where((e) => e.amount != 0)
        .map((e) => _ForecastItem(
            date: e.date,
            name: e.title,
            amount: app.convertToMain(e.amount.abs(), e.currency),
            type: e.amount > 0 ? 'income' : 'expense',
            source: e.kind == 'invoice'
                ? 'Fatura'
                : e.kind == 'recurring'
                    ? 'Recorrente'
                    : 'Pendente'))
        .toList();
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

  String _normaliseMerchant(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'\d+'), '')
        .replaceAll(RegExp(r'[^a-záàâãéêíóôõúç ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<_RecurringSuggestion> _detectRecurringSuggestions(DateTime now) {
    final existingNames = app.recurring
        .map((r) => _normaliseMerchant(r.name))
        .where((e) => e.isNotEmpty)
        .toSet();
    final grouped = <String, List<AppTransaction>>{};
    final since = now.subtract(const Duration(days: 150));

    for (final tx in app.transactions) {
      if (tx.type != 'expense' || tx.date.isBefore(since)) continue;
      if (FinanceRules.isNeutral(tx, metadata[tx.id])) continue;
      final key = _normaliseMerchant(tx.description);
      if (key.length < 3 || existingNames.contains(key)) continue;
      (grouped[key] ??= []).add(tx);
    }

    final suggestions = <_RecurringSuggestion>[];
    for (final entry in grouped.entries) {
      final list = entry.value..sort((a, b) => a.date.compareTo(b.date));
      if (list.length < 2) continue;

      final recent = list.length > 4 ? list.sublist(list.length - 4) : list;
      final intervals = <int>[];
      for (var i = 1; i < recent.length; i++) {
        intervals
            .add(recent[i].date.difference(recent[i - 1].date).inDays.abs());
      }
      if (intervals.isEmpty) continue;
      final monthlyLike = intervals.every((days) => days >= 20 && days <= 40);
      if (!monthlyLike) continue;

      final avgAmount =
          recent.map(_mainAmount).reduce((a, b) => a + b) / recent.length;
      final maxDiff = recent
          .map((tx) => (_mainAmount(tx) - avgAmount).abs())
          .fold<double>(0, (a, b) => a > b ? a : b);
      if (avgAmount > 0 && maxDiff / avgAmount > .20) continue;

      final last = recent.last;
      suggestions.add(_RecurringSuggestion(
        name: last.description.trim().isEmpty ? entry.key : last.description,
        amount: avgAmount,
        occurrences: recent.length,
        lastDate: last.date,
      ));
    }

    suggestions.sort((a, b) => b.amount.compareTo(a.amount));
    return suggestions.take(5).toList();
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
        .where((r) =>
            r.paymentType == 'expense' && r.recurringType == 'subscription')
        .toList();
    final subscriptionsMonthly = subscriptions.fold<double>(
      0,
      (sum, r) => sum + _monthlyEquivalent(r),
    );

    final suggestions = _detectRecurringSuggestions(now);

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
    final historical =
        recentMonths.map(_expenseForMonth).where((v) => v > 0).toList();
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
    final reserveMonths =
        averageExpense > 0 ? reserveValue / averageExpense : 0.0;

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
                  'Fluxo dos próximos 30 dias',
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
                  _money(netForecast),
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
                        value: _money(expectedIncome),
                        icon: Icons.south_west_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _Metric(
                        label: 'Saídas previstas',
                        value: _money(expectedExpense),
                        icon: Icons.north_east_rounded,
                        danger: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          TextButton.icon(
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AgendaScreen())),
              icon: const Icon(Icons.event_note),
              label: const Text('Ver saldo previsto, detalhes e avisos')),
          const SizedBox(height: 18),
          const _SectionTitle('Inteligência do mês'),
          const SizedBox(height: 8),
          _InsightTile(
            icon: monthDelta == null || monthDelta <= 0
                ? Icons.trending_down_rounded
                : Icons.trending_up_rounded,
            title: 'Comparação com o mês passado',
            value: monthDelta == null
                ? 'Sem base ainda'
                : '${monthDelta >= 0 ? '+' : ''}${monthDelta.toStringAsFixed(1).replaceAll('.', ',')}%',
            subtitle: '${_money(currentExpense)} gastos neste mês',
            danger: monthDelta != null && monthDelta > 10,
          ),
          _InsightTile(
            icon: Icons.category_outlined,
            title: 'Categoria que mais pesa',
            value: topCategory == null
                ? 'Sem gastos'
                : (app.categoryById(topCategory.key)?.name ?? 'Outros'),
            subtitle: topCategory == null
                ? 'Comece registrando seus gastos'
                : _money(topCategory.value),
          ),
          _InsightTile(
            icon: Icons.autorenew_rounded,
            title: 'Assinaturas',
            value:
                '${subscriptions.length} ativa${subscriptions.length == 1 ? '' : 's'}',
            subtitle: '${_money(subscriptionsMonthly)}/mês estimado',
          ),
          _InsightTile(
            icon: Icons.savings_outlined,
            title: 'Reserva estimada',
            value: reserveMonths <= 0
                ? 'Sem cobertura calculável'
                : '${reserveMonths.toStringAsFixed(1).replaceAll('.', ',')} meses',
            subtitle: '${_money(reserveValue)} em poupança/metas',
          ),
          if (currentIncome > 0)
            _InsightTile(
              icon: Icons.percent_rounded,
              title: 'Comprometimento da renda',
              value:
                  '${((currentExpense / currentIncome) * 100).toStringAsFixed(0)}%',
              subtitle: '${_money(currentExpense)} de ${_money(currentIncome)}',
              danger: currentExpense > currentIncome,
            ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 18),
            const _SectionTitle('Possíveis recorrências detectadas'),
            const SizedBox(height: 4),
            Text(
              'O app encontrou cobranças parecidas em meses diferentes. Revise antes de cadastrar como recorrente.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ...suggestions.map(
              (item) => Card(
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.auto_awesome_rounded),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item.occurrences} cobranças parecidas • última em ${DateFormat('dd/MM').format(item.lastDate)}',
                  ),
                  trailing: Text(
                    '${_money(item.amount)}/mês',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ),
          ],
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
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
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
                        value: risk.ratio.clamp(0.0, 1.0).toDouble(),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${_money(risk.spent)} de ${_money(risk.budget.amount)}',
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
                  'Nenhum vencimento ou pagamento recorrente previsto para os próximos 30 dias.',
                ),
              ),
            )
          else
            ...forecast.take(14).map(
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
                        '${DateFormat('dd/MM/yyyy').format(item.date)} • ${item.source}',
                      ),
                      trailing: Text(
                        '${item.type == 'income' ? '+' : '-'}${_money(item.amount)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color:
                              item.type == 'income' ? Colors.green : cs.error,
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
              maxLines: 2, style: Theme.of(context).textTheme.labelSmall),
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
          backgroundColor:
              (danger ? cs.error : cs.primary).withValues(alpha: .12),
          child: Icon(icon, color: danger ? cs.error : cs.primary),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 125),
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
  final String source;

  const _ForecastItem({
    required this.date,
    required this.name,
    required this.amount,
    required this.type,
    required this.source,
  });
}

class _RecurringSuggestion {
  final String name;
  final double amount;
  final int occurrences;
  final DateTime lastDate;

  const _RecurringSuggestion({
    required this.name,
    required this.amount,
    required this.occurrences,
    required this.lastDate,
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
