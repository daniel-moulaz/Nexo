// lib/screens/budget_screen.dart
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/savings_goal_sheet.dart';
import 'savings_goal_detail_screen.dart';
import '../utils/haptics.dart';
import '../utils/finance_input.dart';
import '../utils/snackbar.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  static void _openSheet(BuildContext context, {Budget? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _BudgetSheet(existing: existing),
    );
  }

  @override
  State<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends State<BudgetScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final app = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final cur = app.settings.currency;

    final overCount = app.budgets.where(app.budgetExceeded).length;

    final goals = app.savingsGoals;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Planejamento'),
          bottom: TabBar(
            controller: _tabCtrl,
            tabs: const [Tab(text: 'Orçamentos'), Tab(text: 'Objetivos')],
          )),
      body: TabBarView(controller: _tabCtrl, children: [
        ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              const Text('Limites por categoria',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(overCount > 0
                  ? '$overCount orçamento(s) acima do limite'
                  : 'Acompanhe os gastos do mês ou da semana.'),
              const SizedBox(height: 16),
              if (app.budgets.isEmpty)
                EmptyState(
                    icon: Icons.pie_chart_outline,
                    message: l10n.budget_noBudgetsYet,
                    subMessage: 'Toque em Adicionar orçamento para começar.'),
              ...app.budgets.map((b) => _BudgetCard(budget: b, app: app)),
              FilledButton.icon(
                  onPressed: () => BudgetScreen._openSheet(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar orçamento')),
            ]),
        ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              _SumChip(
                  label: 'Total guardado',
                  value: formatAmount(app.totalSaved, cur),
                  color: cs.primary),
              const SizedBox(height: 16),
              if (goals.isEmpty)
                const EmptyState(
                    icon: Icons.savings_outlined,
                    message: 'Qual é o seu próximo objetivo?',
                    subMessage: 'Defina uma meta e acompanhe seus aportes.'),
              ...goals.map((g) => _GoalCard(goal: g, app: app)),
              FilledButton.icon(
                  onPressed: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const SavingsGoalSheet()),
                  icon: const Icon(Icons.add),
                  label: const Text('Adicionar objetivo')),
            ]),
      ]),
    );
  }
}

// ── Summary chip ──────────────────────────────────────────────────────────────
class _SumChip extends StatelessWidget {
  final String label, value;
  final Color color;
  const _SumChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Budget card ───────────────────────────────────────────────────────────────
class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final AppProvider app;
  const _BudgetCard({required this.budget, required this.app});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spent = app.budgetSpent(budget);
    final ratio = budget.amount <= 0 ? 0.0 : spent / budget.amount;
    final color = ratio >= 1
        ? cs.error
        : ratio >= .75
            ? Colors.orange.shade800
            : cs.primary;
    final remaining = budget.amount - spent;
    final name = app.categoryById(budget.categoryId)?.name ?? 'Categoria';
    return Card(
        child: InkWell(
            onTap: () => BudgetScreen._openSheet(context, existing: budget),
            onLongPress: () async {
              if (await showDeleteConfirm(context, name) && context.mounted) {
                final undo = await app.deleteBudgetWithUndo(budget.id);
                if (context.mounted)
                  showAppSnackbar(context, 'Orçamento excluído', onUndo: undo);
              }
            },
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(budget.period == 'weekly'
                          ? 'Esta semana'
                          : 'Este mês'),
                      const SizedBox(height: 12),
                      Wrap(spacing: 16, runSpacing: 8, children: [
                        Text(
                            'Gasto: ${formatAmount(spent, app.settings.currency)}'),
                        Text(
                            'Limite: ${formatAmount(budget.amount, app.settings.currency)}'),
                      ]),
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                          value: ratio.clamp(0, 1), color: color, minHeight: 7),
                      const SizedBox(height: 8),
                      Text(
                          '${(ratio * 100).toStringAsFixed(0)}% usado • ${remaining < 0 ? 'Excedido em' : 'Restante'} ${formatAmount(remaining.abs(), app.settings.currency)}',
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w600)),
                    ]))));
  }
}

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final AppProvider app;
  const _GoalCard({required this.goal, required this.app});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = app.goalProgress(goal);
    final isCompleted = goal.isCompleted;
    final barColor = isCompleted ? const Color(0xFF2E7D32) : cs.primary;
    final color = Color(goal.colorValue);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            ExpensyRoute(builder: (_) => SavingsGoalDetailScreen(goal: goal)),
          );
        },
        onLongPress: () async {
          if (await showDeleteConfirm(context, goal.name) && context.mounted) {
            final undo = await context
                .read<AppProvider>()
                .deleteSavingsGoalWithUndo(goal.id);
            if (context.mounted) {
              showAppSnackbar(
                context,
                'Excluído: ${goal.name}',
                onUndo: undo,
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.savings_outlined, color: color, size: 19),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      if (goal.targetDate != null)
                        Text(
                          'Prazo: ${ptDate(goal.targetDate!)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.5)),
                        ),
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  formatAmount(goal.currentAmount, goal.currency),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: barColor),
                ),
                Text(
                  isCompleted
                      ? 'Concluído'
                      : 'de ${formatAmount(goal.targetAmount, goal.currency)}',
                  style: TextStyle(
                      fontSize: 10,
                      color: isCompleted
                          ? const Color(0xFF2E7D32)
                          : cs.onSurface.withValues(alpha: 0.5)),
                ),
              ]),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                color: barColor,
                backgroundColor: barColor.withValues(alpha: 0.15),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Budget sheet ──────────────────────────────────────────────────────────────
class _BudgetSheet extends StatefulWidget {
  final Budget? existing;
  const _BudgetSheet({this.existing});
  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final _amtCtrl = TextEditingController();
  String? _categoryId;
  String _period = 'monthly';
  bool _submitted = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      final e = widget.existing!;
      _amtCtrl.text = e.amount.toStringAsFixed(2);
      _categoryId = e.categoryId;
      _period = e.period;
    } else {
      // Default to first expense category not yet budgeted
      final app = context.read<AppProvider>();
      final expCats = app.categories.where((c) => c.type == 'expense').toList();
      final budgetedIds = app.budgets.map((b) => b.categoryId).toSet();
      final free = expCats.where((c) => !budgetedIds.contains(c.id)).toList();
      if (free.isNotEmpty) {
        _categoryId = free.first.id;
      } else if (expCats.isNotEmpty) _categoryId = expCats.first.id;
    }
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);
    final amount = parseMoney(_amtCtrl.text);
    if (amount == null || amount <= 0 || _categoryId == null) return;
    final app = context.read<AppProvider>();
    final l10n = AppLocalizations.of(context)!;

    // Guard: if adding and category already has a budget, block it
    if (!isEdit) {
      final existing = app.budgetForCategory(_categoryId!);
      if (existing != null) {
        if (!mounted) return;
        showAppSnackbar(context, l10n.budget_thisCategoryAlreadyH);
        return;
      }
    }

    final b = Budget(
      id: isEdit ? widget.existing!.id : app.newId(),
      categoryId: _categoryId!,
      amount: amount,
      period: _period,
      createdAt: isEdit ? widget.existing!.createdAt : DateTime.now(),
    );

    if (isEdit) {
      await app.updateBudget(b);
    } else {
      await app.addBudget(b);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final app = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final sym = currencyInfo(app.settings.currency).symbol;
    final expCats = app.categories.where((c) => c.type == 'expense').toList();

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          left: 20,
          right: 20,
          top: 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEdit ? l10n.budget_editBudget : l10n.budget_setBudget,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),

            // Amount
            TextField(
              controller: _amtCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.budget_budgetAmount,
                prefixText: '$sym ',
                errorText: _submitted && (parseMoney(_amtCtrl.text) ?? 0) <= 0
                    ? l10n.error_required
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // Period selector
            Text(l10n.budget_period,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(letterSpacing: 1)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _period = 'monthly'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _period == 'monthly'
                          ? cs.primary
                          : cs.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(l10n.budget_monthly,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _period == 'monthly'
                                  ? cs.onPrimary
                                  : cs.primary)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _period = 'weekly'),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _period == 'weekly'
                          ? cs.secondary
                          : cs.secondaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(l10n.budget_weekly,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _period == 'weekly'
                                  ? cs.onSecondary
                                  : cs.secondary)),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Category
            if (expCats.isNotEmpty) ...[
              Text(l10n.budget_category,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(letterSpacing: 1)),
              const SizedBox(height: 8),
              CategoryChipPicker(
                categories: expCats,
                selectedId: _categoryId,
                onSelected: (id) => setState(() => _categoryId = id),
              ),
              const SizedBox(height: 16),
            ],

            // Preview
            if (_categoryId != null &&
                parseMoney(_amtCtrl.text) != null &&
                parseMoney(_amtCtrl.text)! > 0) ...[
              Builder(builder: (ctx) {
                final spent = app.budgetSpent(Budget(
                  id: '',
                  categoryId: _categoryId!,
                  amount: parseMoney(_amtCtrl.text)!,
                  period: _period,
                  createdAt: DateTime.now(),
                ));
                final budgetAmt = parseMoney(_amtCtrl.text)!;
                final pct = (spent / budgetAmt).clamp(0.0, 1.0);
                final catName = app.categoryById(_categoryId!)?.name ?? '';
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.budget_previewFor(catName),
                            style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.6))),
                        const SizedBox(height: 6),
                        Wrap(spacing: 12, runSpacing: 4, children: [
                          Text(
                              l10n.budget_spentAmount(
                                  formatAmount(spent, app.settings.currency)),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          Text(
                              l10n.budget_ofAmount(formatAmount(
                                  budgetAmt, app.settings.currency)),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurface.withValues(alpha: 0.5))),
                        ]),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 5,
                            backgroundColor: cs.primary.withValues(alpha: 0.12),
                            valueColor: AlwaysStoppedAnimation<Color>(pct >= 1.0
                                ? cs.error
                                : pct >= 0.75
                                    ? Colors.orange
                                    : cs.primary),
                          ),
                        ),
                      ]),
                );
              }),
              const SizedBox(height: 16),
            ],

            FilledButton.icon(
              onPressed: () {
                AppHaptics.tap(context, HapticStrength.light);
                _submit();
              },
              icon: Icon(isEdit ? Icons.save_outlined : Icons.add),
              label: Text(
                  isEdit ? l10n.budget_saveChanges : l10n.budget_setBudget),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28)),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
