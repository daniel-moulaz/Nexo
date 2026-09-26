import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import 'finance_export_screen.dart';
import 'statement_import_screen.dart';

class FinanceHomeScreen extends StatefulWidget {
  const FinanceHomeScreen({super.key});

  @override
  State<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends State<FinanceHomeScreen> {
  Future<Map<String, TransactionMetadata>>? _metaFuture;
  int _lastTxCount = -1;

  Future<Map<String, TransactionMetadata>> _metadata(AppProvider app) {
    if (_metaFuture == null || _lastTxCount != app.transactions.length) {
      _lastTxCount = app.transactions.length;
      _metaFuture = TransactionMetadataService.instance
          .getForMany(app.transactions.map((e) => e.id));
    }
    return _metaFuture!;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return FutureBuilder<Map<String, TransactionMetadata>>(
      future: _metadata(app),
      builder: (context, snapshot) {
        final metadata = snapshot.data ?? const <String, TransactionMetadata>{};
        return _Dashboard(app: app, metadata: metadata);
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
      'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
      'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
    ];
    return '${months[date.month - 1]} de ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();
    final monthTx = app.transactions.where((t) => _currentMonth(t.date)).toList();

    double income = 0;
    double paid = 0;
    double pending = 0;
    double extraordinary = 0;
    int overdueCount = 0;

    for (final tx in monthTx) {
      final amount = _mainAmount(tx);
      if (tx.type == 'income') {
        income += amount;
        continue;
      }
      final meta = metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      if (meta.excludeFromSpending) continue;
      if (meta.status == 'pending') {
        pending += amount;
        if (meta.isOverdue) overdueCount++;
      } else {
        paid += amount;
      }
      if (meta.expenseClass == 'extraordinary') extraordinary += amount;
    }

    final committed = paid + pending;
    final available = income - committed;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final remainingDays = (daysInMonth - now.day + 1).clamp(1, 31);
    final safeDaily = available > 0 ? available / remainingDays : 0.0;
    final safeWeekly = safeDaily * 7;
    final normalCost = (paid - extraordinary).clamp(0.0, double.infinity);

    final pendingTx = monthTx.where((t) {
      if (t.type != 'expense') return false;
      final meta = metadata[t.id];
      return meta?.status == 'pending';
    }).toList()
      ..sort((a, b) {
        final da = metadata[a.id]?.dueDate ?? a.date;
        final db = metadata[b.id]?.dueDate ?? b.date;
        return da.compareTo(db);
      });

    final cards = app.accounts.where((a) => a.type == 'credit').toList();

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              app.settings.userName.trim().isEmpty
                  ? 'Meu Fluxo'
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
            tooltip: 'Importar extrato',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StatementImportScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Exportar Excel',
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FinanceExportScreen()),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 130),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Disponível após compromissos',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      )),
                  const SizedBox(height: 4),
                  Text(
                    formatAmount(available, app.settings.currency),
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: available < 0 ? cs.error : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _MiniStat(
                          label: 'Receitas',
                          value: formatAmount(income, app.settings.currency),
                          icon: Icons.arrow_downward_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniStat(
                          label: 'Pago',
                          value: formatAmount(paid, app.settings.currency),
                          icon: Icons.check_circle_outline_rounded,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MiniStat(
                          label: 'Pendente',
                          value: formatAmount(pending, app.settings.currency),
                          icon: Icons.schedule_rounded,
                          danger: overdueCount > 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _InsightCard(
                    title: 'Ritmo seguro',
                    main: '${formatAmount(safeDaily, app.settings.currency)}/dia',
                    subtitle: '${formatAmount(safeWeekly, app.settings.currency)}/semana',
                    icon: Icons.speed_rounded,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InsightCard(
                    title: 'Custo normal',
                    main: formatAmount(normalCost, app.settings.currency),
                    subtitle: extraordinary > 0
                        ? 'Extra: ${formatAmount(extraordinary, app.settings.currency)}'
                        : 'Sem extras no mês',
                    icon: Icons.home_work_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const _SectionHeader(
              title: 'Atalhos',
              trailing: 'Organize tudo por aqui',
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
                      formatAmount(_mainAmount(tx), app.settings.currency),
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
                trailing: 'Faturas estimadas',
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
                      ? 'Reservas/metas: ${formatAmount(app.totalSaved, app.settings.currency)}'
                      : 'Acompanhe contas, reservas e bens',
                ),
                trailing: Text(
                  formatAmount(
                    app.totalBalanceAll + app.totalAssetsValue,
                    app.settings.currency,
                  ),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ],
        ),
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

  DateTime _safeDate(int year, int month, int day) {
    final max = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, max));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final closeDay = card.statementDay ?? 1;
    final currentClose = _safeDate(now.year, now.month, closeDay);
    final DateTime cycleEnd;
    final DateTime cycleStart;

    if (!now.isAfter(currentClose)) {
      cycleEnd = currentClose;
      final prevMonthEnd = _safeDate(now.year, now.month - 1, closeDay);
      cycleStart = prevMonthEnd.add(const Duration(days: 1));
    } else {
      cycleStart = currentClose.add(const Duration(days: 1));
      cycleEnd = _safeDate(now.year, now.month + 1, closeDay);
    }

    final purchases = app.transactions.where((t) {
      if (t.accountId != card.id || t.type != 'expense') return false;
      if (t.date.isBefore(cycleStart) || t.date.isAfter(cycleEnd)) return false;
      final meta = metadata[t.id];
      return !(meta?.excludeFromSpending ?? false);
    });
    final total = purchases.fold<double>(0, (sum, t) => sum + t.amount);
    final limit = card.creditLimit;
    final available = limit == null
        ? null
        : (limit - total).clamp(0.0, double.infinity).toDouble();

    final dueDay = card.dueDay;
    DateTime? due;
    if (dueDay != null) {
      final dueMonth = cycleEnd.month == 12 ? 1 : cycleEnd.month + 1;
      final dueYear = cycleEnd.month == 12 ? cycleEnd.year + 1 : cycleEnd.year;
      due = _safeDate(dueYear, dueMonth, dueDay);
    }

    return Card(
      elevation: 0,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Color(card.colorValue).withValues(alpha: 0.16),
          child: Icon(Icons.credit_card_rounded, color: Color(card.colorValue)),
        ),
        title: Text(card.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text([
          'Fecha ${DateFormat('dd/MM').format(cycleEnd)}',
          if (due != null) 'vence ${DateFormat('dd/MM').format(due)}',
          if (available != null) 'limite livre ${formatAmount(available, card.currency)}',
        ].join(' • ')),
        trailing: Text(
          formatAmount(total, card.currency),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        onTap: () => app.tabIndexNotifier.value = 3,
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
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900)),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
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
          Text(main,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
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
          child: Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
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
