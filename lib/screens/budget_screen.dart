// lib/screens/budget_screen.dart
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../services/budget_insights.dart';
import '../theme/app_theme.dart';
import '../widgets/nexo_ui.dart';
import '../widgets/shared_widgets.dart';
import '../widgets/savings_goal_sheet.dart';
import 'savings_goal_detail_screen.dart';
import '../utils/haptics.dart';
import '../utils/finance_input.dart';
import '../utils/snackbar.dart';

class BudgetScreen extends StatefulWidget {
  const BudgetScreen({super.key});

  static void _openSheet(BuildContext context,
      {Budget? existing, String? categoryId, double? amount}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _BudgetSheet(
          existing: existing, categoryId: categoryId, amount: amount),
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
    final hidden = app.settings.hideBalance;
    String money(double v) =>
        hidden ? '••••' : formatAmount(v, app.settings.currency);
    final now = DateTime.now();
    final suggestions = suggestBudgets(
        transactions: app.transactions,
        metadata: app.transactionMetadata,
        categories: app.categories,
        budgets: app.budgets,
        toMain: (t) => app.convertToMain(
            t.amount,
            t.currency.isNotEmpty
                ? t.currency
                : app.accountById(t.accountId)?.currency ??
                    app.settings.currency),
        now: now);
    double used(Budget b) => app.budgetProgressRaw(b);
    // Closest to the limit first: that is what needs attention.
    final budgets = [...app.budgets]
      ..sort((a, b) => used(b).compareTo(used(a)));
    final goals = app.savingsGoals;
    return Scaffold(
      appBar: AppBar(
          title: const Text('Planejamento'),
          bottom: TabBar(
            controller: _tabCtrl,
            tabs: const [Tab(text: 'Orçamentos'), Tab(text: 'Objetivos')],
          )),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _tabCtrl.index == 0
              ? BudgetScreen._openSheet(context)
              : showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => const SavingsGoalSheet()),
          icon: const Icon(Icons.add),
          label: Text(_tabCtrl.index == 0 ? 'Orçamento' : 'Objetivo')),
      body: TabBarView(controller: _tabCtrl, children: [
        ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (budgets.isNotEmpty) ...[
                _BudgetSummary(app: app, money: money, now: now),
                const SizedBox(height: 16),
                const NexoSectionTitle('Limites por categoria',
                    subtitle: 'Toque para alterar; segure para excluir'),
                const SizedBox(height: 8),
              ] else
                EmptyState(
                    icon: Icons.pie_chart_outline,
                    message: l10n.budget_noBudgetsYet,
                    subMessage:
                        'Defina quanto quer gastar por categoria e o Nexo mostra quanto ainda cabe por dia.'),
              for (final b in budgets)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _BudgetCard(
                        budget: b, app: app, money: money, now: now)),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                const NexoSectionTitle('Sugestões',
                    subtitle: 'Pela média dos últimos 3 meses',
                    icon: Icons.auto_awesome_outlined),
                const SizedBox(height: 8),
                NexoCard(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(children: [
                      for (final s in suggestions)
                        ListTile(
                            leading:
                                CategoryDot(category: s.category, size: 36),
                            title: Text(s.category.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('Média de ${money(s.average)}/mês'),
                            trailing: TextButton(
                                onPressed: () => BudgetScreen._openSheet(
                                    context,
                                    categoryId: s.category.id,
                                    amount: s.amount),
                                child: Text(hidden
                                    ? 'Criar'
                                    : 'Limitar a ${_whole(s.amount, app.settings.currency)}'))),
                    ])),
              ],
            ]),
        ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              if (goals.isEmpty)
                const EmptyState(
                    icon: Icons.savings_outlined,
                    message: 'Qual é o seu próximo objetivo?',
                    subMessage:
                        'Defina uma meta e o Nexo diz quanto guardar por mês.')
              else ...[
                _GoalsSummary(app: app, money: money),
                const SizedBox(height: 16),
              ],
              for (final g in goals)
                Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child:
                        _GoalCard(goal: g, app: app, hidden: hidden, now: now)),
            ]),
      ]),
    );
  }
}

/// R$ 300,00 → R$ 300: suggestions are round numbers.
String _whole(double v, String currency) =>
    formatAmount(v, currency).replaceAll(RegExp(r'[,.]00$'), '');

// ── Month summary ─────────────────────────────────────────────────────────────
class _BudgetSummary extends StatelessWidget {
  const _BudgetSummary(
      {required this.app, required this.money, required this.now});
  final AppProvider app;
  final String Function(double) money;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthly = app.budgets.where((b) => b.period != 'weekly').toList();
    final over = app.budgets.where(app.budgetExceeded).length;
    final limit = monthly.fold(0.0, (s, b) => s + app.budgetLimit(b));
    final spent = monthly.fold(0.0, (s, b) => s + app.budgetSpent(b));
    final pace = budgetPace(
        Budget(
            id: '',
            categoryId: '',
            amount: limit,
            period: 'monthly',
            createdAt: now),
        spent,
        now);
    final onHero = cs.onPrimaryContainer;
    return NexoCard(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.tertiaryContainer]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(limit > 0 ? 'Orçado no mês' : 'Orçamentos da semana',
            style: TextStyle(
                color: onHero.withValues(alpha: .75),
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (limit > 0) ...[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: money(spent),
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: onHero,
                      fontFeatures: NexoTones.figures)),
              TextSpan(
                  text: '  de ${money(limit)}',
                  style: TextStyle(
                      fontSize: 15, color: onHero.withValues(alpha: .75))),
            ])),
          ),
          const SizedBox(height: 12),
          NexoProgress(value: spent / limit, height: 10),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: NexoStatPill(
                    label: spent <= limit ? 'Ainda cabe' : 'Acima',
                    value: money((limit - spent).abs()))),
            const SizedBox(width: 8),
            Expanded(
                child:
                    NexoStatPill(label: 'Por dia', value: money(pace.perDay))),
            const SizedBox(width: 8),
            Expanded(
                child: NexoStatPill(
                    label: 'Faltam', value: '${pace.daysLeft} dias')),
          ]),
        ] else
          Text('${app.budgets.length} limite(s) semanal(is)',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: onHero)),
        if (over > 0) ...[
          const SizedBox(height: 12),
          Row(children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: NexoTones.expense(context)),
            const SizedBox(width: 6),
            Expanded(
                child: Text('$over categoria(s) passaram do limite',
                    style:
                        TextStyle(color: onHero, fontWeight: FontWeight.w600))),
          ]),
        ],
      ]),
    );
  }
}

// ── Budget card ───────────────────────────────────────────────────────────────
class _BudgetCard extends StatelessWidget {
  final Budget budget;
  final AppProvider app;
  final String Function(double) money;
  final DateTime now;
  const _BudgetCard(
      {required this.budget,
      required this.app,
      required this.money,
      required this.now});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final spent = app.budgetSpent(budget);
    final window =
        budgetWindow(budget, now, weekStart: app.settings.weekStart);
    final limit = window.limit;
    final ratio = limit <= 0 ? 0.0 : spent / limit;
    final color = ratio >= 1
        ? NexoTones.expense(context)
        : ratio >= .8
            ? NexoTones.warning(context)
            : cs.primary;
    final remaining = limit - spent;
    final category = app.categoryById(budget.categoryId);
    final name = category?.name ?? 'Categoria';
    final pace = budgetPace(budget, spent, now,
        weekStart: app.settings.weekStart, limit: limit);
    final projection = pace.projection;
    final String status;
    if (remaining < 0) {
      status = 'Passou ${money(-remaining)} do limite';
    } else if (projection != null &&
        !window.partial &&
        projection > limit * 1.05) {
      status = 'No ritmo atual fecha o mês em ${money(projection)}';
    } else {
      status =
          'Cabe ${money(pace.perDay)} por dia · ${pace.daysLeft} dia(s) restante(s)';
    }
    return NexoCard(
        padding: EdgeInsets.zero,
        child: InkWell(
            onTap: () => BudgetScreen._openSheet(context, existing: budget),
            onLongPress: () async {
              if (await showDeleteConfirm(context, name) && context.mounted) {
                final undo = await app.deleteBudgetWithUndo(budget.id);
                if (context.mounted) {
                  showAppSnackbar(context, 'Orçamento excluído', onUndo: undo);
                }
              }
            },
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CategoryDot(category: category, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700)),
                              Text(
                                  budget.period == 'weekly'
                                      ? 'Esta semana'
                                      : 'Este mês',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: cs.onSurfaceVariant)),
                            ])),
                        _Amounts(
                            top: money(spent),
                            bottom: window.partial
                                ? 'de ${money(limit)} (proporcional)'
                                : 'de ${money(limit)}',
                            color: color),
                      ]),
                      const SizedBox(height: 12),
                      NexoProgress(value: ratio),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: Text(status,
                                maxLines: 2,
                                style: TextStyle(
                                    fontSize: 12.5,
                                    color: remaining < 0
                                        ? color
                                        : cs.onSurfaceVariant,
                                    fontWeight: remaining < 0
                                        ? FontWeight.w700
                                        : FontWeight.w500))),
                        const SizedBox(width: 8),
                        Text('${(ratio * 100).toStringAsFixed(0)}%',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, color: color)),
                      ]),
                    ]))));
  }
}

/// Right-aligned amount pair that shrinks instead of overflowing.
class _Amounts extends StatelessWidget {
  const _Amounts({required this.top, required this.bottom, this.color});
  final String top, bottom;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(top,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: color ?? cs.onSurface,
                  fontFeatures: NexoTones.figures)),
          Text(bottom,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ]),
      ),
    );
  }
}

// ── Goals ─────────────────────────────────────────────────────────────────────
class _GoalsSummary extends StatelessWidget {
  const _GoalsSummary({required this.app, required this.money});
  final AppProvider app;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final open = app.savingsGoals.where((g) => !g.isCompleted).toList();
    final target = open.fold(
        0.0, (s, g) => s + app.convertToMain(g.targetAmount, g.currency));
    final saved = open.fold(
        0.0, (s, g) => s + app.convertToMain(g.currentAmount, g.currency));
    final done = app.savingsGoals.length - open.length;
    final onHero = cs.onPrimaryContainer;
    return NexoCard(
      gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primaryContainer, cs.tertiaryContainer]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Total guardado',
            style: TextStyle(
                color: onHero.withValues(alpha: .75),
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(money(app.totalSaved),
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: onHero,
                    fontFeatures: NexoTones.figures))),
        if (target > 0) ...[
          const SizedBox(height: 12),
          NexoProgress(value: saved / target, height: 10),
          const SizedBox(height: 8),
          Text(
              'Faltam ${money(target - saved < 0 ? 0 : target - saved)} para ${open.length} objetivo(s) em andamento',
              style: TextStyle(color: onHero.withValues(alpha: .85))),
        ],
        if (done > 0) ...[
          const SizedBox(height: 4),
          Text('$done concluído(s)',
              style: TextStyle(color: onHero.withValues(alpha: .75))),
        ],
      ]),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final AppProvider app;
  final bool hidden;
  final DateTime now;
  const _GoalCard(
      {required this.goal,
      required this.app,
      required this.hidden,
      required this.now});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String money(double v) => hidden ? '••••' : formatAmount(v, goal.currency);
    final progress = app.goalProgress(goal);
    final isCompleted = goal.isCompleted;
    final done = NexoTones.income(context);
    final color = Color(goal.colorValue);
    final monthly = goalMonthlyNeeded(goal, now);
    final missing = goal.targetAmount - goal.currentAmount;
    final late = !isCompleted &&
        missing > 0 &&
        goal.targetDate != null &&
        goal.targetDate!.isBefore(DateTime(now.year, now.month, now.day));
    final String line;
    if (isCompleted || missing <= 0) {
      line = 'Meta atingida';
    } else if (late) {
      line = 'O prazo passou · faltam ${money(missing)}';
    } else if (monthly != null) {
      line = 'Guarde ${money(monthly)}/mês até ${ptDate(goal.targetDate!)}';
    } else {
      line = 'Faltam ${money(missing)}';
    }

    return NexoCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            ExpensyRoute(builder: (_) => SavingsGoalDetailScreen(goal: goal)),
          );
        },
        onLongPress: () async {
          if (await showDeleteConfirm(context, goal.name) && context.mounted) {
            final VoidCallback undo;
            try {
              undo = await context
                  .read<AppProvider>()
                  .deleteSavingsGoalWithUndo(goal.id);
            } on FormatException catch (e) {
              if (context.mounted) showAppSnackbar(context, e.message);
              return;
            }
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
                child: Icon(
                    isCompleted
                        ? Icons.emoji_events_outlined
                        : Icons.savings_outlined,
                    color: color,
                    size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(goal.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              _Amounts(
                  top: money(goal.currentAmount),
                  bottom: 'de ${money(goal.targetAmount)}',
                  color: isCompleted ? done : null),
            ]),
            const SizedBox(height: 12),
            NexoProgress(value: isCompleted ? 1 : progress),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                  child: Text(line,
                      maxLines: 2,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: late
                              ? NexoTones.warning(context)
                              : isCompleted
                                  ? done
                                  : cs.onSurfaceVariant,
                          fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Text('${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ── Budget sheet ──────────────────────────────────────────────────────────────
class _BudgetSheet extends StatefulWidget {
  final Budget? existing;
  final String? categoryId;
  final double? amount;
  const _BudgetSheet({this.existing, this.categoryId, this.amount});
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
    } else if (widget.categoryId != null) {
      _categoryId = widget.categoryId;
      _amtCtrl.text = widget.amount?.toStringAsFixed(2) ?? '';
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
