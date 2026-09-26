import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';

class SavingsGoalSheet extends StatefulWidget {
  final SavingsGoal? existing;

  const SavingsGoalSheet({super.key, this.existing});

  @override
  State<SavingsGoalSheet> createState() => _SavingsGoalSheetState();
}

class _SavingsGoalSheetState extends State<SavingsGoalSheet> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  DateTime? _targetDate;
  int _color = 0xFF6750A4;
  bool _submitted = false;
  bool _saving = false;

  bool get isEdit => widget.existing != null;

  static const _colors = [
    0xFF6750A4,
    0xFF1565C0,
    0xFF2E7D32,
    0xFFC62828,
    0xFFE65100,
    0xFF00838F,
    0xFF6A1B9A,
    0xFF37474F,
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _amountCtrl.text = existing.targetAmount.toStringAsFixed(2).replaceAll('.', ',');
      _targetDate = existing.targetDate;
      _color = existing.colorValue;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final name = _nameCtrl.text.trim();
    final amount = parseMoney(_amountCtrl.text);
    if (name.isEmpty || amount == null || amount <= 0) return;

    setState(() => _saving = true);
    final app = context.read<AppProvider>();
    final existing = widget.existing;
    final goal = SavingsGoal(
      id: existing?.id ?? app.newId(),
      name: name,
      targetAmount: amount,
      currentAmount: existing?.currentAmount ?? 0,
      currency: existing?.currency ?? app.settings.currency,
      targetDate: _targetDate,
      colorValue: _color,
      isCompleted: existing?.isCompleted ?? false,
      createdAt: existing?.createdAt ?? DateTime.now(),
      completedAt: existing?.completedAt,
    );

    if (existing == null) {
      await app.addSavingsGoal(goal);
    } else {
      await app.updateSavingsGoal(goal);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final amount = parseMoney(_amountCtrl.text);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isEdit ? 'Editar objetivo' : 'Novo objetivo',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Nome do objetivo',
                hintText: 'Ex.: reserva de emergência, viagem, notebook...',
                prefixIcon: const Icon(Icons.flag_outlined),
                errorText: _submitted && _nameCtrl.text.trim().isEmpty
                    ? 'Informe um nome.'
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Valor da meta',
                prefixText: '${currencyInfo(app.settings.currency).symbol} ',
                errorText: _submitted && (amount == null || amount <= 0)
                    ? 'Informe um valor válido.'
                    : null,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: const Icon(Icons.event_outlined),
              title: const Text('Prazo (opcional)'),
              subtitle: Text(_targetDate == null ? 'Sem data definida' : ptDate(_targetDate!)),
              trailing: _targetDate == null
                  ? const Icon(Icons.chevron_right_rounded)
                  : IconButton(
                      tooltip: 'Remover prazo',
                      onPressed: () => setState(() => _targetDate = null),
                      icon: const Icon(Icons.clear_rounded),
                    ),
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _targetDate ?? now.add(const Duration(days: 180)),
                  firstDate: now,
                  lastDate: DateTime(now.year + 50),
                  cancelText: 'Cancelar',
                  confirmText: 'Selecionar',
                );
                if (picked != null) setState(() => _targetDate = picked);
              },
            ),
            const SizedBox(height: 12),
            Text('Cor', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _colors.map((value) {
                final selected = _color == value;
                return GestureDetector(
                  onTap: () => setState(() => _color = value),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Color(value),
                      shape: BoxShape.circle,
                      border: selected ? Border.all(color: cs.onSurface, width: 3) : null,
                    ),
                    child: selected ? const Icon(Icons.check_rounded, color: Colors.white) : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(isEdit ? 'Salvar alterações' : 'Criar objetivo'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
