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
          IconButton(
            tooltip: 'Receitas',
            icon: const Icon(Icons.savings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IncomesScreen()),
            ),
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
          return _body(app, expenses, metadata);
        },
      ),
    );
  }

  Widget _body(
    AppProvider app,
    List<AppTransaction> expenses,
    Map<String, TransactionMetadata> metadata,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    double paid = 0;
    double pending = 0;
    int overdue = 0;

    for (final tx in expenses) {
      final meta =
          metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      if (FinanceRules.isNeutral(tx, meta)) continue;
      final amount = _mainAmount(app, tx);
      if (meta.status == 'pending') {
        pending += amount;
        if (meta.isOverdue) overdue++;
      } else {
        paid += amount;
      }
    }

    final visible = expenses.where((tx) {
      final meta =
          metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      final neutral = FinanceRules.isNeutral(tx, meta);
      switch (_filter) {
        case 'pending':
          return !neutral && meta.status == 'pending' && !meta.isOverdue;
        case 'overdue':
          return !neutral && meta.isOverdue;
        case 'extra':
          return !neutral && meta.expenseClass == 'extraordinary';
        case 'neutral':
          return neutral;
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
                  formatAmount(paid + pending, app.settings.currency),
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
                _filterChip('Todos', 'all'),
                _filterChip('Pendentes', 'pending'),
                _filterChip('Atrasados', 'overdue'),
                _filterChip('Extraordinários', 'extra'),
                _filterChip('Transfer./Reserva', 'neutral'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: visible.isEmpty
              ? _emptyState(theme, cs)
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
                          final category =
                              _categoryLabel(app.categoryById(tx.categoryId));
                          final account = app.accountById(tx.accountId);
                          final neutral = FinanceRules.isNeutral(tx, meta);
                          final status = neutral
                              ? 'Não conta como gasto'
                              : meta.isOverdue
                                  ? 'Atrasado'
                                  : meta.status == 'pending'
                                      ? 'Pendente'
                                      : 'Pago';
                          final details = <String>[
                            if (account != null) account.name,
                            if (meta.subcategory.isNotEmpty)
                              '$category › ${meta.subcategory}'
                            else
                              category,
                            if (meta.installmentLabel.isNotEmpty)
                              'Parcela ${meta.installmentLabel}',
                          ];

                          return Card(
                            elevation: 0,
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              onTap: () => _openTransaction(tx),
                              leading: CircleAvatar(
                                child: Icon(
                                  neutral
                                      ? Icons.swap_horiz_rounded
                                      : Icons.arrow_upward_rounded,
                                ),
                              ),
                              title: Text(
                                tx.description.trim().isEmpty
                                    ? category
                                    : tx.description.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              subtitle: Text(
                                '${details.join(' • ')}\n$status',
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              isThreeLine: true,
                              trailing: Text(
                                formatAmount(
                                  tx.amount,
                                  _currencyFor(app, tx),
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
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

  Widget _filterChip(String label, String value) {
    return ChoiceChip(
      label: Text(label),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _emptyState(ThemeData theme, ColorScheme cs) {
    final filtered = _filter != 'all';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              filtered
                  ? Icons.filter_alt_off_outlined
                  : Icons.receipt_long_outlined,
              size: 64,
              color: cs.onSurfaceVariant.withValues(alpha: 0.55),
            ),
            const SizedBox(height: 16),
            Text(
              filtered
                  ? 'Nenhuma despesa neste filtro'
                  : 'Nenhuma despesa em ${_monthLabel(_selectedMonth)}',
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
