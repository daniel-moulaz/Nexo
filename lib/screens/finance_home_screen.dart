import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/finance_rules.dart';
import '../services/billing_cycle.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import 'card_invoice_screen.dart';
import 'agenda_screen.dart';
import 'add_transaction_screen.dart';
import 'transfer_screen.dart';
import 'finance_export_screen.dart';
import 'financial_planning_screen.dart';
import 'incomes_screen.dart';
import 'statement_import_screen.dart';
import 'transaction_search_screen.dart';

class FinanceHomeScreen extends StatefulWidget {
  const FinanceHomeScreen({super.key});

  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> {
  Future<Map<String, TransactionMetadata>>? _metaFuture;
  int _lastTxCount = -1;
  int _lastMetaRevision = -1;

  Future<Map<String, TransactionMetadata>> _metadata(
    AppProvider app,
    int revision,
  ) {
    if (_metaFuture == null ||
        _lastTxCount != app.transactions.length ||
        _lastMetaRevision != revision) {
      _lastTxCount = app.transactions.length;
      _lastMetaRevision = revision;
      _metaFuture = TransactionMetadataService.instance
          .getForMany(app.transactions.map((e) => e.id));
    }
    return _metaFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return ValueListenableBuilder<int>(
      valueListenable: TransactionMetadataService.instance.revision,
      builder: (context, revision, _) {
        return FutureBuilder<Map<String, TransactionMetadata>>(
          future: _metadata(app, revision),
          builder: (context, snapshot) {
            final metadata =
                snapshot.data ?? const <String, TransactionMetadata>{};
            return _Dashboard(app: app, metadata: metadata);
          },
        );
      },
    );
  }
}

class _Dashboard extends StatelessWidget {
  final AppProvider app;
  final Map<String, TransactionMetadata> metadata;

  const _Dashboard({required this.app, required this.metadata});

  String _currencyFor(AppTransaction tx) {
    if (tx.currency.isNotEmpty) return tx.currency;
    return app.accountById(tx.accountId)?.currency ?? app.settings.currency;
  }

  double _mainAmount(AppTransaction tx) =>
      app.convertToMain(tx.amount, _currencyFor(tx));

  bool _currentMonth(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  String _monthLabel(DateTime date) {
    const months = [
      'janeiro',
      'fevereiro',
      'março',
      'abril',
      'maio',
      'junho',
      'julho',
      'agosto',
      'setembro',
      'outubro',
      'novembro',
      'dezembro',
    ];
    return '${months[date.month - 1]} de ${date.year}';
  }

  String _money(double value, [String? currency]) {
    if (app.settings.hideBalance) return '••••••';
    return formatAmount(value, currency ?? app.settings.currency);
  }

  Future<void> _openMenuDestination(BuildContext context, String value) async {
    switch (value) {
      case 'planning':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinancialPlanningScreen()),
        );
        break;
      case 'import':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StatementImportScreen()),
        );
        break;
      case 'export':
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FinanceExportScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final monthTx =
        app.transactions.where((t) => _currentMonth(t.date)).toList();

    double income = 0;
    double paid = 0;
    double pending = 0;
    double extraordinary = 0;
    int overdueCount = 0;

    for (final tx in monthTx) {
      final meta = metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      if (FinanceRules.isNeutral(tx, meta)) continue;
      final amount = _mainAmount(tx);
      if (tx.type == 'income') {
        if (!meta.isPending) income += amount;
        continue;
      }
      if (meta.status == 'pending') {
        pending += amount;
        if (meta.isOverdue) overdueCount++;
      } else {
        paid += amount;
      }
      if (meta.expenseClass == 'extraordinary') extraordinary += amount;
    }

    final cash = app.cashAccounts
        .where((a) => !a.excludeFromTotal)
        .fold<double>(
            0, (sum, a) => sum + app.convertToMain(a.balance, a.currency));
    final cardDebt = app.accounts.where((a) => a.type == 'credit').fold<double>(
        0,
        (sum, a) =>
            sum +
            app.convertToMain(
                -a.balance.clamp(double.negativeInfinity, 0).toDouble(),
                a.currency));
    final available = cash - pending - cardDebt;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final remainingDays = (daysInMonth - now.day + 1).clamp(1, 31);
    final safeDaily = available > 0 ? available / remainingDays : 0.0;
    final safeWeekly = safeDaily * 7;
    final normalCost =
        (paid - extraordinary).clamp(0.0, double.infinity).toDouble();

    final pendingTx = monthTx.where((t) {
      if (t.type != 'expense') return false;
      final meta = metadata[t.id];
      if (FinanceRules.isNeutral(t, meta)) return false;
      return meta?.status == 'pending';
    }).toList()
      ..sort((a, b) {
        final da = metadata[a.id]?.dueDate ?? a.date;
        final db = metadata[b.id]?.dueDate ?? b.date;
        return da.compareTo(db);
      });

    final cards = app.accounts.where((a) => a.type == 'credit').toList();
    final subscriptions = app.recurring
        .where((r) =>
            r.paymentType == 'expense' && r.recurringType == 'subscription')
        .toList();
    final monthlySubscriptions = subscriptions.fold<double>(0, (sum, r) {
      final amount = app.convertToMain(
        r.amount,
        app.accountById(r.accountId)?.currency ?? app.settings.currency,
      );
      switch (r.freqUnit) {
        case 'days':
          return sum + amount * (30 / r.freqVal);
        case 'weeks':
          return sum + amount * (4.345 / r.freqVal);
        case 'years':
          return sum + amount / (12 * r.freqVal);
        default:
          return sum + amount / r.freqVal;
      }
    });

    final riskyBudgets = app.budgets.where((b) {
      if (b.amount <= 0) return false;
      return app.budgetSpent(b) / b.amount >= .75;
    }).length;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              app.settings.userName.trim().isEmpty
                  ? 'Nexo'
                  : 'Olá, ${app.settings.userName.split(' ').first}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            Text(
              _monthLabel(now),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
              tooltip: 'Agenda financeira',
              icon: const Icon(Icons.event_note),
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const AgendaScreen()))),
          IconButton(
            tooltip: app.settings.hideBalance
                ? 'Mostrar valores'
                : 'Ocultar valores',
            icon: Icon(app.settings.hideBalance
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined),
            onPressed: () => app.updateSetting(
              'hideBalance',
              !app.settings.hideBalance,
            ),
          ),
          IconButton(
            tooltip: 'Buscar lançamentos',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const TransactionSearchScreen()),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais ações',
            onSelected: (value) => _openMenuDestination(context, value),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'planning',
                child: ListTile(
                  leading: Icon(Icons.insights_outlined),
                  title: Text('Planejamento'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('Importar extrato'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.table_view_outlined),
                  title: Text('Exportar relatório'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Saldo em contas',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _money(cash),
                  style: theme.textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    color: available < 0 ? cs.error : null,
                  ),
                ),
                Text(
                    'Após pendências do mês e dívida total dos cartões: ${_money(available)}'),
                TextButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const AgendaScreen())),
                    icon: const Icon(Icons.event_note),
                    label: const Text(
                        'Ver saldo previsto e próximos compromissos')),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MiniStat(
                        label: 'Receitas',
                        value: _money(income),
                        icon: Icons.arrow_downward_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: 'Gastos do mês',
                        value: _money(paid),
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _MiniStat(
                        label: overdueCount > 0
                            ? 'Pendente ($overdueCount atraso${overdueCount == 1 ? '' : 's'})'
                            : 'Pendente',
                        value: _money(pending),
                        icon: Icons.schedule_rounded,
                        danger: overdueCount > 0,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final action in [
              ('expense', 'Despesa', Icons.remove),
              ('income', 'Receita', Icons.add),
              ('transfer', 'Transferência', Icons.swap_horiz)
            ])
              FilledButton.tonalIcon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => action.$1 == 'transfer'
                              ? const TransferScreen()
                              : AddTransactionScreen(initialType: action.$1))),
                  icon: Icon(action.$3),
                  label: Text(action.$2)),
          ]),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InsightCard(
                  title: 'Ritmo seguro',
                  main: app.settings.hideBalance
                      ? '••••••'
                      : '${formatAmount(safeDaily, app.settings.currency)}/dia',
                  subtitle: app.settings.hideBalance
                      ? '••••••'
                      : '${formatAmount(safeWeekly, app.settings.currency)}/semana',
                  icon: Icons.speed_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _InsightCard(
                  title: 'Custo normal',
                  main: _money(normalCost),
                  subtitle: extraordinary > 0
                      ? 'Extra: ${_money(extraordinary)}'
                      : 'Sem extras no mês',
                  icon: Icons.home_work_outlined,
                ),
              ),
            ],
          ),
          if (subscriptions.isNotEmpty || riskyBudgets > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (subscriptions.isNotEmpty)
                  Expanded(
                    child: _InsightCard(
                      title: 'Assinaturas',
                      main: '${subscriptions.length}',
                      subtitle: app.settings.hideBalance
                          ? 'custo mensal oculto'
                          : '${formatAmount(monthlySubscriptions, app.settings.currency)}/mês',
                      icon: Icons.autorenew_rounded,
                    ),
                  ),
                if (subscriptions.isNotEmpty && riskyBudgets > 0)
                  const SizedBox(width: 10),
                if (riskyBudgets > 0)
                  Expanded(
                    child: _InsightCard(
                      title: 'Orçamentos',
                      main: '$riskyBudgets em atenção',
                      subtitle: 'acima de 75% do limite',
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          const _SectionHeader(
            title: 'Atalhos',
            trailing: 'Tudo que você usa mais',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickAction(
                label: 'Despesas',
                icon: Icons.receipt_long_rounded,
                onTap: () => app.tabIndexNotifier.value = 1,
              ),
              _QuickAction(
                label: 'Receitas',
                icon: Icons.south_west_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IncomesScreen()),
                ),
              ),
              _QuickAction(
                label: 'Planejamento',
                icon: Icons.insights_rounded,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FinancialPlanningScreen(),
                  ),
                ),
              ),
              _QuickAction(
                label: 'Recorrentes',
                icon: Icons.repeat_rounded,
                onTap: () => app.tabIndexNotifier.value = 2,
              ),
              _QuickAction(
                label: 'Contas e cartões',
                icon: Icons.credit_card_rounded,
                onTap: () => app.tabIndexNotifier.value = 3,
              ),
              _QuickAction(
                label: 'Orçamento',
                icon: Icons.pie_chart_rounded,
                onTap: () => app.tabIndexNotifier.value = 4,
              ),
            ],
          ),
          if (pendingTx.isNotEmpty) ...[
            const SizedBox(height: 22),
            _SectionHeader(
              title: overdueCount > 0
                  ? 'Pendências • $overdueCount atrasada${overdueCount == 1 ? '' : 's'}'
                  : 'Próximos vencimentos',
              trailing: '${pendingTx.length} no mês',
            ),
            const SizedBox(height: 8),
            ...pendingTx.take(5).map((tx) {
              final meta = metadata[tx.id]!;
              final due = meta.dueDate;
              return Card(
                elevation: 0,
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(meta.isOverdue
                        ? Icons.priority_high_rounded
                        : Icons.schedule_rounded),
                  ),
                  title: Text(
                    tx.description.trim().isEmpty
                        ? (app.categoryById(tx.categoryId)?.name ?? 'Despesa')
                        : tx.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(due == null
                      ? 'Sem vencimento'
                      : '${meta.isOverdue ? 'Atrasada' : 'Vence'} em ${DateFormat('dd/MM').format(due)}'),
                  trailing: Text(
                    _money(_mainAmount(tx)),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: meta.isOverdue ? cs.error : null,
                    ),
                  ),
                ),
              );
            }),
          ],
          if (cards.isNotEmpty) ...[
            const SizedBox(height: 22),
            const _SectionHeader(
              title: 'Cartões',
              trailing: 'Toque para abrir a fatura',
            ),
            const SizedBox(height: 8),
            ...cards.map((card) => _CardInvoiceTile(
                  app: app,
                  card: card,
                  metadata: metadata,
                )),
          ],
          const SizedBox(height: 22),
          const _SectionHeader(
            title: 'Seu patrimônio',
            trailing: 'Contas + bens',
          ),
          const SizedBox(height: 8),
          Card(
            elevation: 0,
            child: ListTile(
              leading: const CircleAvatar(
                child: Icon(Icons.account_balance_rounded),
              ),
              title: const Text('Saldo total'),
              subtitle: Text(
                app.totalSaved > 0
                    ? 'Reservas/metas: ${_money(app.totalSaved)}'
                    : 'Acompanhe contas, reservas e bens',
              ),
              trailing: Text(
                _money(app.totalBalanceAll + app.totalAssetsValue),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardInvoiceTile extends StatelessWidget {
  final AppProvider app;
  final Account card;
  final Map<String, TransactionMetadata> metadata;

  const _CardInvoiceTile({
    required this.app,
    required this.card,
    required this.metadata,
  });

  String _display(double value, String currency) {
    if (app.settings.hideBalance) return '••••••';
    return formatAmount(value, currency);
  }

  @override
  Widget build(BuildContext context) {
    final cycle =
        BillingCycle.forDate(DateTime.now(), card.statementDay, card.dueDay);
    final cycleStart = cycle.start;
    final cycleEnd = cycle.end;
    final purchases = app.transactions.where((t) {
      if (t.accountId != card.id) return false;
      if (t.date.isBefore(cycleStart) ||
          !t.date.isBefore(cycleEnd.add(const Duration(days: 1)))) return false;
      return !FinanceRules.isNeutral(t, metadata[t.id]) ||
          metadata[t.id]?.source == 'opening_balance';
    });
    final total = purchases.fold<double>(
        0, (sum, t) => sum + (t.type == 'income' ? -t.amount : t.amount));
    final limit = card.creditLimit;
    final available = limit == null
        ? null
        : (limit + card.balance.clamp(double.negativeInfinity, 0))
            .clamp(0.0, double.infinity)
            .toDouble();

    final due = cycle.due;

    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(card.colorValue).withValues(alpha: 0.16),
          child: Icon(Icons.credit_card_rounded, color: Color(card.colorValue)),
        ),
        title: Text(
          card.name == 'Credit Card' ? 'Cartão de crédito' : card.name,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text([
          'Fecha ${DateFormat('dd/MM').format(cycleEnd)}',
          if (due != null) 'vence ${DateFormat('dd/MM').format(due)}',
          if (available != null)
            'limite livre ${_display(available, card.currency)}',
        ].join(' • ')),
        trailing: Text(
          _display(total, card.currency),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CardInvoiceScreen(cardId: card.id),
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: danger ? cs.error : cs.primary),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final String title;
  final String main;
  final String subtitle;
  final IconData icon;

  const _InsightCard({
    required this.title,
    required this.main,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary),
          const SizedBox(height: 10),
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            main,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;

  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
        ),
        Text(trailing, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ActionChip(
      avatar: Icon(icon, size: 18, color: cs.primary),
      label: Text(label),
      onPressed: onTap,
    );
  }
}
