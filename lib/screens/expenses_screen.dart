import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import 'add_transaction_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late DateTime _selectedMonth;

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

  bool _isSameMonth(DateTime date) {
    return date.year == _selectedMonth.year && date.month == _selectedMonth.month;
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

  String _dayLabel(DateTime date) {
    const months = [
      'JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN',
      'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]}';
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

  String _currencyFor(AppProvider app, AppTransaction transaction) {
    if (transaction.currency.isNotEmpty) return transaction.currency;
    return app.accountById(transaction.accountId)?.currency ?? app.settings.currency;
  }

  String _formatAmount(double amount, String currency) {
    if (currency == 'BRL') {
      return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(amount);
    }
    try {
      return NumberFormat.simpleCurrency(name: currency).format(amount);
    } catch (_) {
      return '$currency ${amount.toStringAsFixed(2)}';
    }
  }

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

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final expenses = app.transactions
        .where((t) => t.type == 'expense' && _isSameMonth(t.date))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Despesas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Voltar para o mês atual',
            onPressed: () {
              final now = DateTime.now();
              setState(() => _selectedMonth = DateTime(now.year, now.month));
            },
            icon: const Icon(Icons.today_outlined),
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
          return _ExpensesBody(
            selectedMonth: _selectedMonth,
            monthLabel: _monthLabel(_selectedMonth),
            expenses: expenses,
            metadata: metadata,
            app: app,
            dayLabel: _dayLabel,
            categoryLabel: _categoryLabel,
            formatAmount: _formatAmount,
            currencyFor: _currencyFor,
            onPreviousMonth: () => _changeMonth(-1),
            onNextMonth: () => _changeMonth(1),
            onOpenTransaction: _openTransaction,
          );
        },
      ),
    );
  }
}

class _ExpensesBody extends StatelessWidget {
  final DateTime selectedMonth;
  final String monthLabel;
  final List<AppTransaction> expenses;
  final Map<String, TransactionMetadata> metadata;
  final AppProvider app;
  final String Function(DateTime) dayLabel;
  final String Function(AppCategory?) categoryLabel;
  final String Function(double, String) formatAmount;
  final String Function(AppProvider, AppTransaction) currencyFor;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final Future<void> Function([AppTransaction?]) onOpenTransaction;

  const _ExpensesBody({
    required this.selectedMonth,
    required this.monthLabel,
    required this.expenses,
    required this.metadata,
    required this.app,
    required this.dayLabel,
    required this.categoryLabel,
    required this.formatAmount,
    required this.currencyFor,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onOpenTransaction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final baseCurrency = app.settings.currency;

    final total = expenses.fold<double>(0, (sum, item) => sum + item.amount);
    double paidTotal = 0;
    double pendingTotal = 0;
    int pendingCount = 0;
    int overdueCount = 0;

    for (final expense in expenses) {
      final meta = metadata[expense.id] ??
          TransactionMetadata(transactionId: expense.id);
      if (meta.isPending) {
        pendingTotal += expense.amount;
        pendingCount++;
        if (meta.isOverdue) overdueCount++;
      } else {
        paidTotal += expense.amount;
      }
    }

    final grouped = <DateTime, List<AppTransaction>>{};
    for (final transaction in expenses) {
      final day = DateTime(
        transaction.date.year,
        transaction.date.month,
        transaction.date.day,
      );
      (grouped[day] ??= []).add(transaction);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Mês anterior',
                      onPressed: onPreviousMonth,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        monthLabel,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Próximo mês',
                      onPressed: onNextMonth,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Total comprometido',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  formatAmount(total, baseCurrency),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryMetric(
                        label: 'Pago',
                        amount: formatAmount(paidTotal, baseCurrency),
                        icon: Icons.check_circle_outline_rounded,
                        color: Colors.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryMetric(
                        label: 'Pendente',
                        amount: formatAmount(pendingTotal, baseCurrency),
                        icon: Icons.schedule_rounded,
                        color: overdueCount > 0 ? cs.error : Colors.orange,
                      ),
                    ),
                  ],
                ),
                if (pendingCount > 0) ...[
                  const SizedBox(height: 9),
                  Text(
                    overdueCount > 0
                        ? '$pendingCount pendente(s) • $overdueCount atrasado(s)'
                        : '$pendingCount despesa(s) pendente(s)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: overdueCount > 0 ? cs.error : cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: expenses.isEmpty
              ? _EmptyMonth(month: monthLabel)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 170),
                  itemCount: days.length,
                  itemBuilder: (context, dayIndex) {
                    final day = days[dayIndex];
                    final dayTransactions = grouped[day]!;
                    final dayTotal = dayTransactions.fold<double>(
                      0,
                      (sum, item) => sum + item.amount,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            4,
                            dayIndex == 0 ? 6 : 16,
                            4,
                            7,
                          ),
                          child: Row(
                            children: [
                              Text(
                                dayLabel(day),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.primary,
                                  letterSpacing: 0.4,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                formatAmount(dayTotal, baseCurrency),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...dayTransactions.map((transaction) {
                          final meta = metadata[transaction.id] ??
                              TransactionMetadata(
                                transactionId: transaction.id,
                              );
                          return _ExpenseTile(
                            transaction: transaction,
                            metadata: meta,
                            account: app.accountById(transaction.accountId),
                            category: app.categoryById(transaction.categoryId),
                            categoryLabel: categoryLabel(
                              app.categoryById(transaction.categoryId),
                            ),
                            amountLabel: formatAmount(
                              transaction.amount,
                              currencyFor(app, transaction),
                            ),
                            onTap: () => onOpenTransaction(transaction),
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
}

class _SummaryMetric extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  const _SummaryMetric({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  amount,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final AppTransaction transaction;
  final TransactionMetadata metadata;
  final Account? account;
  final AppCategory? category;
  final String categoryLabel;
  final String amountLabel;
  final VoidCallback onTap;

  const _ExpenseTile({
    required this.transaction,
    required this.metadata,
    required this.account,
    required this.category,
    required this.categoryLabel,
    required this.amountLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final categoryColor = Color(category?.colorValue ?? cs.primary.toARGB32());
    final title = transaction.description.trim().isEmpty
        ? categoryLabel
        : transaction.description.trim();

    final statusLabel = metadata.isOverdue
        ? 'Atrasado'
        : metadata.isPending
            ? 'Pendente'
            : 'Pago';
    final statusIcon = metadata.isOverdue
        ? Icons.error_outline_rounded
        : metadata.isPending
            ? Icons.schedule_rounded
            : Icons.check_circle_outline_rounded;
    final statusColor = metadata.isOverdue
        ? cs.error
        : metadata.isPending
            ? Colors.orange
            : Colors.green;

    final categoryPath = metadata.subcategory.isEmpty
        ? categoryLabel
        : '$categoryLabel › ${metadata.subcategory}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: categoryColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  color: categoryColor,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          amountLabel,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (account != null)
                      Text(
                        account!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (metadata.isPending && metadata.dueDate != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Vence em ${DateFormat('dd/MM/yyyy').format(metadata.dueDate!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _InfoChip(
                          icon: Icons.category_outlined,
                          label: categoryPath,
                          color: categoryColor,
                        ),
                        _InfoChip(
                          icon: statusIcon,
                          label: statusLabel,
                          color: statusColor,
                        ),
                      ],
                    ),
                    if (transaction.note.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        transaction.note.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  final String month;

  const _EmptyMonth({required this.month});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 0, 32, 92),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.receipt_long_outlined,
                size: 32,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Nenhuma despesa em $month',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Toque em + Despesa para fazer o primeiro lançamento do mês.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
