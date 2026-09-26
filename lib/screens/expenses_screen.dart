import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/finance_rules.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import 'finance_export_screen.dart';
import 'incomes_screen.dart';
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

  bool _sameMonth(DateTime date) =>
      date.year == _selectedMonth.year && date.month == _selectedMonth.month;

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + delta,
      );
    });
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Escolha uma data do mês desejado',
      cancelText: 'Cancelar',
      confirmText: 'Selecionar mês',
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedMonth = DateTime(picked.year, picked.month));
  }

  String _monthLabel(DateTime date) {
    const months = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
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

  void _openImport() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StatementImportScreen()),
    );
  }

  void _openExport() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FinanceExportScreen()),
    );
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
        title: const Text(
          'Despesas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton.icon(
            tooltip: 'Abrir receitas',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IncomesScreen()),
            ),
            icon: const Icon(Icons.savings_outlined, size: 19),
            label: const Text('Receitas'),
          ),
          IconButton(
            tooltip: 'Escolher mês',
            icon: const Icon(Icons.calendar_month_rounded),
            onPressed: _pickMonth,
          ),
          PopupMenuButton<String>(
            tooltip: 'Mais opções',
            onSelected: (value) {
              if (value == 'import') _openImport();
              if (value == 'export') _openExport();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'import',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.upload_file_outlined),
                  title: Text('Importar extrato'),
                ),
              ),
              PopupMenuItem(
                value: 'export',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.table_view_outlined),
                  title: Text('Exportar Excel'),
                ),
              ),
            ],
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
          final metadata =
              snapshot.data ?? const <String, TransactionMetadata>{};
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
      final meta =
          metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      final amount = _mainAmount(app, tx);
      if (FinanceRules.isNeutral(tx, meta)) {
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
      final meta =
          metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      final neutralTx = FinanceRules.isNeutral(tx, meta);
      switch (_filter) {
        case 'pending':
          return !neutralTx && meta.status == 'pending' && !meta.isOverdue;
        case 'overdue':
          return !neutralTx && meta.isOverdue;
        case 'extra':
          return !neutralTx && meta.expenseClass == 'extraordinary';
        case 'neutral':
          return neutralTx;
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
                      tooltip: 'Mês anterior',
                      onPressed: () => _changeMonth(-1),
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _pickMonth,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _monthLabel(_selectedMonth),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Próximo mês',
                      onPressed: () => _changeMonth(1),
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Total comprometido',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
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
                        label: overdue > 0
                            ? 'Pendente • $overdue atraso${overdue == 1 ? '' : 's'}'
                            : 'Pendente',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _FilterChip(
                    label: 'Todos',
                    value: 'all',
                    current: _filter,
                    onTap: _setFilter),
                _FilterChip(
                    label: 'Pendentes',
                    value: 'pending',
                    current: _filter,
                    onTap: _setFilter),
                _FilterChip(
                    label: 'Atrasados',
                    value: 'overdue',
                    current: _filter,
                    onTap: _setFilter),
                _FilterChip(
                    label: 'Extraordinários',
                    value: 'extra',
                    current: _filter,
                    onTap: _setFilter),
                _FilterChip(
                    label: 'Transfer./Reserva',
                    value: 'neutral',
                    current: _filter,
                    onTap: _setFilter),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: visible.isEmpty
              ? _EmptyState(
                  month: _monthLabel(_selectedMonth),
                  filter: _filter,
                )
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
                            DateFormat('dd MMM', 'pt_BR')
                                .format(day)
                                .toUpperCase(),
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
                            neutral: FinanceRules.isNeutral(tx, meta),
                            account: app.accountById(tx.accountId),
                            categoryLabel:
                                _categoryLabel(app.categoryById(tx.categoryId)),
                            amount: formatAmount(
                              tx.amount,
                              _currencyFor(app, tx),
                            ),
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
                                  await _updateMeta(
                                    tx,
                                    meta,
                                    expenseClass: 'normal',
                                  );
                                  break;
                                case 'extra':
                                  await _updateMeta(
                                    tx,
                                    meta,
                                    expenseClass: 'extraordinary',
                                  );
                                  break;
                                case 'exclude':
                                  await _updateMeta(
                                    tx,
                                    meta,
                                    excludeFromSpending: true,
                                  );
                                  break;
                                case 'include':
                                  await _updateMeta(
                                    tx,
                                    meta,
                                    excludeFromSpending: false,
                                  );
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
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
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
    return ChoiceChip(
      label: Text(label),
      selected: current == value,
      onSelected: (_) => onTap(value),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final AppTransaction tx;
  final TransactionMetadata meta;
  final bool neutral;
  final Account? account;
  final String categoryLabel;
  final String amount;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  const _ExpenseTile({
    required this.tx,
    required this.meta,
    required this.neutral,
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
    final title =
        tx.description.trim().isEmpty ? categoryLabel : tx.description.trim();
    final statusLabel = neutral
        ? 'Não conta como gasto'
        : meta.isOverdue
            ? 'Atrasado'
            : meta.status == 'pending'
                ? 'Pendente'
                : 'Pago';

    final details = <String>[
      if (account != null) account!.name,
      if (meta.subcategory.isNotEmpty)
        '$categoryLabel › ${meta.subcategory}'
      else
        categoryLabel,
      if (meta.installmentLabel.isNotEmpty) 'Parcela ${meta.installmentLabel}',
    ];

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: neutral
                    ? cs.surfaceContainerHighest
                    : cs.errorContainer.withValues(alpha: 0.55),
                child: Icon(
                  neutral
                      ? Icons.swap_horiz_rounded
                      : Icons.arrow_upward_rounded,
                  color: neutral ? cs.onSurfaceVariant : cs.error,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.join(' • '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _Badge(
                          label: statusLabel,
                          danger: meta.isOverdue,
                        ),
                        if (meta.expenseClass == 'extraordinary')
                          const _Badge(label: 'Extraordinário'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Ações rápidas',
                    onSelected: onAction,
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: meta.status == 'pending' ? 'paid' : 'pending',
                        child: Text(meta.status == 'pending'
                            ? 'Marcar como pago'
                            : 'Marcar como pendente'),
                      ),
                      PopupMenuItem(
                        value: meta.expenseClass == 'extraordinary'
                            ? 'normal'
                            : 'extra',
                        child: Text(meta.expenseClass == 'extraordinary'
                            ? 'Marcar como normal'
                            : 'Marcar como extraordinário'),
                      ),
                      PopupMenuItem(
                        value: neutral ? 'include' : 'exclude',
                        child: Text(neutral
                            ? 'Voltar a contar como gasto'
                            : 'Não contar como gasto'),
                      ),
                    ],
                  ),
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
  final bool danger;

  const _Badge({required this.label, this.danger = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: danger
            ? cs.errorContainer
            : cs.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: danger ? cs.error : null,
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final filtered = filter != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.receipt_long_outlined,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? 'Nenhuma despesa neste filtro' : 'Nenhuma despesa em $month',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              filtered
                  ? 'Escolha outro filtro para ver os lançamentos do mês.'
                  : 'Use + Despesa ou importe um extrato para começar.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
