import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final expenses = app.transactions
        .where((t) => t.type == 'expense' && _isSameMonth(t.date))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final total = expenses.fold<double>(0, (sum, item) => sum + item.amount);
    final baseCurrency = app.settings.currency;

    final grouped = <DateTime, List<AppTransaction>>{};
    for (final transaction in expenses) {
      final day = DateTime(transaction.date.year, transaction.date.month, transaction.date.day);
      (grouped[day] ??= []).add(transaction);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTransaction(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Despesa'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
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
                        child: Text(
                          _monthLabel(_selectedMonth),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
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
                  const SizedBox(height: 12),
                  Text(
                    'Total do mês',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _formatAmount(total, baseCurrency),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${expenses.length} ${expenses.length == 1 ? 'lançamento' : 'lançamentos'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: expenses.isEmpty
                ? _EmptyMonth(
                    month: _monthLabel(_selectedMonth),
                    onAdd: () => _openTransaction(),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 140),
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
                                  _dayLabel(day),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    color: cs.primary,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  _formatAmount(dayTotal, baseCurrency),
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ...dayTransactions.map(
                            (transaction) => _ExpenseTile(
                              transaction: transaction,
                              account: app.accountById(transaction.accountId),
                              category: app.categoryById(transaction.categoryId),
                              amountLabel: _formatAmount(
                                transaction.amount,
                                _currencyFor(app, transaction),
                              ),
                              onTap: () => _openTransaction(transaction),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final AppTransaction transaction;
  final Account? account;
  final AppCategory? category;
  final String amountLabel;
  final VoidCallback onTap;

  const _ExpenseTile({
    required this.transaction,
    required this.account,
    required this.category,
    required this.amountLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final categoryColor = Color(category?.colorValue ?? cs.primary.toARGB32());
    final title = transaction.description.trim().isEmpty
        ? (category?.name ?? 'Despesa')
        : transaction.description.trim();

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
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (category != null)
                          _InfoChip(
                            icon: Icons.category_outlined,
                            label: category!.name,
                            color: categoryColor,
                          ),
                        const _InfoChip(
                          icon: Icons.check_circle_outline_rounded,
                          label: 'Lançada',
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
  final Color? color;

  const _InfoChip({
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final foreground = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
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
  final VoidCallback onAdd;

  const _EmptyMonth({required this.month, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
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
              'As despesas lançadas neste mês vão aparecer aqui.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar despesa'),
            ),
          ],
        ),
      ),
    );
  }
}
