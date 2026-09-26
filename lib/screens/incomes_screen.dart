import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../services/finance_rules.dart';
import 'add_transaction_screen.dart';

class IncomesScreen extends StatefulWidget {
  const IncomesScreen({super.key});

  @override
  State<IncomesScreen> createState() => _IncomesScreenState();
}

class _IncomesScreenState extends State<IncomesScreen> {
  late DateTime _selectedMonth;

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
    if (category == null) return 'Outras receitas';
    const labels = {
      'salary': 'Salário',
      'freelance': 'Freelancer',
      'business': 'Negócios',
      'investment': 'Investimentos',
      'gift': 'Presentes',
    };
    return labels[category.id] ?? category.name;
  }

  String _currencyFor(AppProvider app, AppTransaction tx) {
    if (tx.currency.isNotEmpty) return tx.currency;
    return app.accountById(tx.accountId)?.currency ?? app.settings.currency;
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

  Future<void> _openTransaction([AppTransaction? existing]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          existing: existing,
          initialType: 'income',
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final incomes = app.transactions
        .where((t) => t.type == 'income' && _sameMonth(t.date) && !FinanceRules.isNeutral(t, app.transactionMetadata[t.id]))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    final total = incomes.where((t) => app.transactionMetadata[t.id]?.isPending != true).fold<double>(0, (sum, tx) {
      final currency = _currencyFor(app, tx);
      return sum + app.convertToMain(tx.amount, currency);
    });

    final grouped = <DateTime, List<AppTransaction>>{};
    for (final tx in incomes) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      (grouped[day] ??= []).add(tx);
    }
    final days = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Receitas',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            tooltip: 'Escolher mês',
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openTransaction(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Receita'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                        child: Text(
                          _monthLabel(_selectedMonth),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
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
                    'Total recebido',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    formatAmount(total, app.settings.currency),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${incomes.length} lançamento${incomes.length == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: incomes.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.savings_outlined,
                            size: 64,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.55),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Nenhuma receita em ${_monthLabel(_selectedMonth)}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Use + Receita para registrar salário, freelas, reembolsos e outras entradas.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 120),
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
                            final account = app.accountById(tx.accountId);
                            final category = app.categoryById(tx.categoryId);
                            final title = tx.description.trim().isEmpty
                                ? _categoryLabel(category)
                                : tx.description.trim();
                            return Card(
                              elevation: 0,
                              child: ListTile(
                                onTap: () => _openTransaction(tx),
                                leading: const CircleAvatar(
                                  child: Icon(Icons.arrow_downward_rounded),
                                ),
                                title: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: Text([
                                  if (account != null) account.name,
                                  _categoryLabel(category),
                                  if ((app.transactionMetadata[tx.id]?.subcategory ?? '').isNotEmpty) app.transactionMetadata[tx.id]!.subcategory,
                                  app.transactionMetadata[tx.id]?.isPending == true ? 'Prevista' : 'Recebida',
                                ].join(' • ')),
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
      ),
    );
  }
}
