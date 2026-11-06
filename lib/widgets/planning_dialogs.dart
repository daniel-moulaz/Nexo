import 'package:flutter/material.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/planning_rules.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';

/// Base plus a share of the month's profit, for one budget's category.
Future<void> showBudgetRuleDialog(
    BuildContext context, AppProvider app, String categoryId) {
  final current = BudgetRule.fromJson(app.settings.budgetRules[categoryId]);
  final base = TextEditingController(
      text: current == null ? '' : current.base.toStringAsFixed(2));
  final percent = TextEditingController(
      text: current == null ? '50' : current.percent.toStringAsFixed(0));
  final incomes = app.categories.where((c) => c.type == 'income').toList();
  var income = current?.incomeCategoryId;
  String? error;
  return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                  title: const Text('Limite variável'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Text(
                        'O limite é a base mais uma parte do lucro do mês (ganhos menos gastos da categoria). Se der prejuízo, fica na base.'),
                    const SizedBox(height: 12),
                    TextField(
                        controller: base,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(labelText: 'Base')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: percent,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: '% do lucro')),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                        initialValue:
                            incomes.any((c) => c.id == income) ? income : null,
                        decoration: const InputDecoration(
                            labelText: 'Categoria dos ganhos'),
                        items: [
                          for (final c in incomes)
                            DropdownMenuItem(value: c.id, child: Text(c.name))
                        ],
                        onChanged: (v) => income = v),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))
                    ],
                  ])),
                  actions: [
                    if (current != null)
                      TextButton(
                          onPressed: () {
                            app.updateSettings({
                              'budgetRules': {...app.settings.budgetRules}
                                ..remove(categoryId)
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Tirar')),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () {
                          final b = parseMoney(base.text);
                          final p = double.tryParse(percent.text);
                          if (b == null ||
                              b < 0 ||
                              p == null ||
                              p < 0 ||
                              p > 100 ||
                              income == null) {
                            setState(() => error =
                                'Informe a base, a % de 0 a 100 e a categoria.');
                            return;
                          }
                          app.updateSettings({
                            'budgetRules': {
                              ...app.settings.budgetRules,
                              categoryId: BudgetRule(
                                      base: b,
                                      percent: p,
                                      incomeCategoryId: income!)
                                  .toJson()
                            }
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Salvar')),
                  ])));
}

/// The goal's target follows the fixed costs from now on.
Future<void> showEmergencyPlanDialog(
    BuildContext context, AppProvider app, SavingsGoal goal) {
  final plan = EmergencyPlan.fromJson(app.settings.emergencyPlan);
  final mine = plan?.goalId == goal.id ? plan : null;
  final months = TextEditingController(text: '${mine?.months ?? 6}');
  final food = TextEditingController(
      text: mine == null ? '' : mine.foodMinimum.toStringAsFixed(2));
  final fixed = monthlyFixedCosts(app.recurring, DateTime.now());
  String? error;
  return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) => AlertDialog(
                  title: const Text('Meta automática'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(
                        'A meta acompanha os custos fixos: hoje as recorrentes somam ${formatAmount(fixed, app.settings.currency)} por mês.'),
                    const SizedBox(height: 12),
                    TextField(
                        controller: months,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Meses')),
                    const SizedBox(height: 12),
                    TextField(
                        controller: food,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            labelText: 'Alimentação mínima por mês')),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))
                    ],
                  ])),
                  actions: [
                    if (mine != null)
                      TextButton(
                          onPressed: () {
                            app.updateSettings(
                                {'emergencyPlan': <String, Object>{}});
                            Navigator.pop(context);
                          },
                          child: const Text('Desligar')),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () async {
                          final m = int.tryParse(months.text);
                          final f = food.text.trim().isEmpty
                              ? 0.0
                              : parseMoney(food.text);
                          if (m == null ||
                              m < 1 ||
                              m > 60 ||
                              f == null ||
                              f < 0) {
                            setState(() => error =
                                'Informe de 1 a 60 meses e um valor válido.');
                            return;
                          }
                          await app.updateSettings({
                            'emergencyPlan': EmergencyPlan(
                                    goalId: goal.id, months: m, foodMinimum: f)
                                .toJson()
                          });
                          await app.applyEmergencyPlan();
                          if (context.mounted) Navigator.pop(context);
                        },
                        child: const Text('Salvar')),
                  ])));
}
