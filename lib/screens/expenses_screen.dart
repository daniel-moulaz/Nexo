import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import 'finance_export_screen.dart';
import 'statement_import_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late DateTime _selectedMonth;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  bool _sameMonth(DateTime date) =>
      date.year == _selectedMonth.year && date.month == _selectedMonth.month;

  String _monthLabel(DateTime date) {
    const months = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _categoryLabel(AppCategory? category) {
    if (category == null) return 'Outros';
    const labels = {
      'food_exp': 'Alimentação',
      'transport': 'Transporte',
      'shopping': 'Compras',
      'bills': 'Moradia & Contas',
      'health': 'Saúde',
      'entertainment': 'Lazer',
      'education': 'Educação',
      'other_exp': 'Outros',
    };
    return labels[category.id] ?? category.name;
  }

  String _currencyFor(AppProvider app, AppTransaction tx) {
    if (tx.currency.isNotEmpty) return tx.currency;
    return app.accountById(tx.accountId)?.currency ?? app.settings.currency;
  }

  double _mainAmount(AppProvider app, AppTransaction tx) =>
      app.convertToMain(tx.amount, _currencyFor(app, tx));

  Future<void> _openTransaction([AppTransaction? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          existing: existing,
          initialType: 'expense',
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _updateMeta(
    AppTransaction tx,
    TransactionMetadata old, {
    String? status,
    String? expenseClass,
    bool? excludeFromSpending,
  }) async {
    final nextStatus = status ?? old.status;
    await TransactionMetadataService.instance.save(
      TransactionMetadata(
        transactionId: tx.id,
        subcategory: old.subcategory,
        status: nextStatus,
        dueDate: nextStatus == 'pending' ? (old.dueDate ?? tx.date) : null,
        expenseClass: expenseClass ?? old.expenseClass,
        excludeFromSpending:
            excludeFromSpending ?? old.excludeFromSpending,
        installmentCurrent: old.installmentCurrent,
        installmentTotal: old.installmentTotal,
        source: old.source,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final expenses = app.transactions
        .where((t) => t.type == 'expense' && _sameMonth(t.date))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Despesas',
            style: TextStyle(fontWeight: FontWeight.w900)),
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
          IconButton(
            tooltip: 'Mês atual',
            icon: const Icon(Icons.today_outlined),
            onPressed: () {
              final now = DateTime.now();
              setState(() => _selectedMonth = DateTime(now.year, now.month));
            },
          ),
        ],
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 76),
        child: FloatingActionButton.extended(
          onPressed: () => _openTransaction(),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Despesa'),
        ),
      ),
      body: FutureBuilder<Map<String, TransactionMetadata>>(
        future: TransactionMetadataService.instance
            .getForMany(expenses.map((e) => e.id)),
        builder: (context, snapshot) {
          final metadata = snapshot.data ?? const <String, TransactionMetadata>{};
          return _buildBody(app, expenses, metadata);
        },
      ),
    );
  }

  Widget _buildBody(
    AppProvider app,
    List<AppTransaction> expenses,
    Map<String, TransactionMetadata> metadata,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    double paid = 0;
    double pending = 0;
    double extraordinary = 0;
    double neutral = 0;
    int overdue = 0;

    for (final tx in expenses) {
      final meta = metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      final amount = _mainAmount(app, tx);
      if (meta.excludeFromSpending) {
        neutral += amount;
        continue;
      }
      if (meta.status == 'pending') {
        pending += amount;
        if (meta.isOverdue) overdue++;
      } else {
        paid += amount;
      }
      if (meta.expenseClass == 'extraordinary') extraordinary += amount;
    }

    final committed = paid + pending;
    final visible = expenses.where((tx) {
      final meta = metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      switch (_filter) {
        case 'pending':
          return meta.status == 'pending' && !meta.isOverdue;
        case 'overdue':
          return meta.isOverdue;
        case 'extra':
          return meta.expenseClass == 'extraordinary' && !meta.excludeFromSpending;
        case 'neutral':
          return meta.excludeFromSpending;
        default:
          return true;
      }
    }).toList();

    final grouped = <DateTime, List<AppTransaction>>{};
    for (final tx in visible) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      (grouped[day] ??= []).add(tx);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        _monthLabel(_selectedMonth),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Total comprometido',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: cs.onSurfaceVariant)),
                Text(
                  formatAmount(committed, app.settings.currency),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryStat(
                        label: 'Pago',
                        value: formatAmount(paid, app.settings.currency),
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryStat(
                        label: overdue > 0 ? 'Pendente • $overdue atraso' : 'Pendente',
                        value: formatAmount(pending, app.settings.currency),
                        icon: Icons.schedule_rounded,
                        danger: overdue > 0,
                      ),
                    ),
                  ],
                ),
                if (extraordinary > 0 || neutral > 0) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (extraordinary > 0)
                        Expanded(
                          child: Text(
                            'Extraordinário: ${formatAmount(extraordinary, app.settings.currency)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      if (neutral > 0)
                        Expanded(
                          child: Text(
                            'Transferências/reserva: ${formatAmount(neutral, app.settings.currency)}',
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(label: 'Todos', value: 'all', current: _filter, onTap: _setFilter),
              _FilterChip(label: 'Pendentes', value: 'pending', current: _filter, onTap: _setFilter),
              _FilterChip(label: 'Atrasados', value: 'overdue', current: _filter, onTap: _setFilter),
              _FilterChip(label: 'Extraordinários', value: 'extra', current: _filter, onTap: _setFilter),
              _FilterChip(label: 'Transfer./Reserva', value: 'neutral', current: _filter, onTap: _setFilter),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(month: _monthLabel(_selectedMonth), filter: _filter)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 170),
                  itemCount: days.length,
                  itemBuilder: (_, dayIndex) {
                    final day = days[dayIndex];
                    final txs = grouped[day]!;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            4,
                            dayIndex == 0 ? 6 : 16,
                            4,
                            6,
                          ),
                          child: Text(
                            DateFormat('dd MMM', 'pt_BR').format(day).toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        ...txs.map((tx) {
                          final meta = metadata[tx.id] ??
                              TransactionMetadata(transactionId: tx.id);
                          return _ExpenseTile(
                            tx: tx,
                            meta: meta,
                            account: app.accountById(tx.accountId),
                            categoryLabel: _categoryLabel(app.categoryById(tx.categoryId)),
                            amount: formatAmount(tx.amount, _currencyFor(app, tx)),
                            onTap: () => _openTransaction(tx),
                            onAction: (action) async {
                              switch (action) {
                                case 'paid':
                                  await _updateMeta(tx, meta, status: 'paid');
                                  break;
                                case 'pending':
                                  await _updateMeta(tx, meta, status: 'pending');
                                  break;
                                case 'normal':
                                  await _updateMeta(tx, meta, expenseClass: 'normal');
                                  break;
                                case 'extra':
                                  await _updateMeta(tx, meta, expenseClass: 'extraordinary');
                                  break;
                                case 'exclude':
                                  await _updateMeta(tx, meta, excludeFromSpending: true);
                                  break;
                                case 'include':
                                  await _updateMeta(tx, meta, excludeFromSpending: false);
                                  break;
                              }
                            },
                          );
                        }),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _setFilter(String value) => setState(() => _filter = value);
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool danger;

  const _SummaryStat({
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
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: danger ? cs.error : cs.primary),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: ChoiceChip(
        label: Text(label),
        selected: current == value,
        onSelected: (_) => onTap(value),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final AppTransaction tx;
  final TransactionMetadata meta;
  final Account? account;
  final String categoryLabel;
  final String amount;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  const _ExpenseTile({
    required this.tx,
    required this.meta,
    required this.account,
    required this.categoryLabel,
    required this.amount,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final title = tx.description.trim().isEmpty ? categoryLabel : tx.description.trim();
    final statusLabel = meta.excludeFromSpending
        ? 'Não conta como gasto'
        : meta.isOverdue
            ? 'Atrasado'
            : meta.status == 'pending'
                ? 'Pendente'
                : 'Pago';
    final statusColor = meta.excludeFromSpending
        ? cs.tertiary
        : meta.isOverdue
            ? cs.error
            : meta.status == 'pending'
                ? cs.secondary
                : Colors.green;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.12),
                child: Icon(
                  meta.excludeFromSpending
                      ? Icons.swap_horiz_rounded
                      : meta.isOverdue
                          ? Icons.priority_high_rounded
                          : Icons.receipt_long_rounded,
                  color: statusColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          amount,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: meta.excludeFromSpending ? cs.onSurface : cs.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      account?.name ?? 'Conta',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Badge(label: categoryLabel, color: cs.primary),
                        if (meta.subcategory.isNotEmpty)
                          _Badge(label: meta.subcategory, color: cs.secondary),
                        _Badge(label: statusLabel, color: statusColor),
                        if (meta.expenseClass == 'extraordinary')
                          _Badge(label: 'Extraordinário', color: cs.tertiary),
                        if (meta.installmentLabel.isNotEmpty)
                          _Badge(label: 'Parcela ${meta.installmentLabel}', color: cs.primary),
                        if (meta.dueDate != null && meta.status == 'pending')
                          _Badge(
                            label: 'Vence ${DateFormat('dd/MM').format(meta.dueDate!)}',
                            color: meta.isOverdue ? cs.error : cs.secondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: onAction,
                itemBuilder: (_) => [
                  if (meta.status == 'pending')
                    const PopupMenuItem(value: 'paid', child: Text('Marcar como pago'))
                  else
                    const PopupMenuItem(value: 'pending', child: Text('Marcar como pendente')),
                  if (meta.expenseClass == 'extraordinary')
                    const PopupMenuItem(value: 'normal', child: Text('Classificar como normal'))
                  else
                    const PopupMenuItem(value: 'extra', child: Text('Marcar extraordinário')),
                  if (meta.excludeFromSpending)
                    const PopupMenuItem(value: 'include', child: Text('Voltar a contar como gasto'))
                  else
                    const PopupMenuItem(value: 'exclude', child: Text('Não contar como gasto')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String month;
  final String filter;

  const _EmptyState({required this.month, required this.filter});

  @override
  Widget build(BuildContext context) {
    final filtered = filter != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined, size: 54),
            const SizedBox(height: 14),
            Text(
              filtered ? 'Nenhum lançamento neste filtro' : 'Nenhuma despesa em $month',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Troque o filtro para ver os demais lançamentos.'
                  : 'Use + Despesa ou importe um extrato para começar.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
