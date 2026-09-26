// lib/screens/add_transaction_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../providers/app_provider.dart';
import '../models/models.dart';
import '../theme/app_theme.dart';
import '../widgets/shared_widgets.dart';
import '../utils/haptics.dart';

class AddTransactionScreen extends StatefulWidget {
  final AppTransaction? existing;
  final String initialType;

  const AddTransactionScreen({
    super.key,
    this.existing,
    this.initialType = 'expense',
  });

  @override
  State<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends State<AddTransactionScreen> {
  final _amtCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  bool _submitted = false;
  bool _dupeWarningDismissed = false;

  late String _type = widget.existing?.type ?? widget.initialType;
  String? _accountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  String _currency = '';

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    final transactableAccounts =
        app.nonBankAccounts.where((a) => !a.isGold).toList();

    if (transactableAccounts.isNotEmpty) {
      _accountId = transactableAccounts.first.id;
      _currency = transactableAccounts.first.currency;
    }

    final cats = app.categories.where((c) => c.type == _type).toList();
    if (cats.isNotEmpty) _categoryId = cats.first.id;

    final e = widget.existing;
    if (e != null) {
      _amtCtrl.text = e.amount.toStringAsFixed(2);
      _descCtrl.text = e.description;
      _noteCtrl.text = e.note;
      _type = e.type;
      _accountId = e.accountId;
      _categoryId = e.categoryId;
      _date = e.date;
      final acc = app.accountById(e.accountId);
      _currency = e.currency.isNotEmpty
          ? e.currency
          : (acc?.currency ?? app.settings.currency);
    }
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _setType(String type) {
    final app = context.read<AppProvider>();
    final cats = app.categories.where((c) => c.type == type).toList();
    setState(() {
      _type = type;
      _categoryId = cats.isNotEmpty ? cats.first.id : null;
    });
  }

  void _onAccountSelected(String? id) {
    if (id == null) return;
    final app = context.read<AppProvider>();
    final acc = app.accountById(id);
    setState(() {
      _accountId = id;
      _currency = acc?.currency ?? app.settings.currency;
    });
  }

  Future<bool?> _showDuplicateWarningDialog(List<AppTransaction> dupes) {
    final l10n = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Possível lançamento duplicado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dupes.length == 1
                  ? 'Já existe um lançamento parecido:'
                  : 'Já existem ${dupes.length} lançamentos parecidos:',
            ),
            const SizedBox(height: 8),
            ...dupes.take(3).map(
                  (d) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '• ${formatAmount(d.amount, d.currency.isNotEmpty ? d.currency : '')} em ${DateFormat('dd/MM').format(d.date)}${d.description.isNotEmpty ? ' — ${d.description}' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.add_transaction_goBack),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar mesmo assim'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    setState(() => _submitted = true);

    final normalizedAmount = _amtCtrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(normalizedAmount);
    if (amount == null || amount <= 0) return;
    if (_accountId == null || _categoryId == null) return;

    final app = context.read<AppProvider>();
    final acc = app.accountById(_accountId!);
    final accCurrency = acc?.currency ?? app.settings.currency;
    final storeCurrency = _currency == accCurrency ? '' : _currency;

    final targetTx = AppTransaction(
      id: isEdit ? widget.existing!.id : app.newId(),
      type: _type,
      amount: amount,
      description: _descCtrl.text.trim(),
      accountId: _accountId!,
      categoryId: _categoryId!,
      date: _date,
      note: _noteCtrl.text.trim(),
      currency: storeCurrency,
    );

    final dupes =
        app.findPossibleDuplicates(targetTx, excludeId: widget.existing?.id);
    if (dupes.isNotEmpty && !_dupeWarningDismissed) {
      final proceed = await _showDuplicateWarningDialog(dupes);
      if (proceed != true) return;
      _dupeWarningDismissed = true;
    }

    if (isEdit) {
      await app.updateTransaction(targetTx, widget.existing!);
    } else {
      await app.addTransaction(targetTx);
    }

    if (mounted) Navigator.pop(context);
  }

  String _screenTitle() {
    if (_type == 'expense') {
      return isEdit ? 'Editar despesa' : 'Nova despesa';
    }
    return isEdit ? 'Editar receita' : 'Nova receita';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cats = app.categories.where((c) => c.type == _type).toList();
    final accounts = app.nonBankAccounts.where((a) => !a.isGold).toList();

    final selectedAccount = app.accountById(_accountId ?? '');
    final accountCurrency = selectedAccount?.currency ?? app.settings.currency;
    final effectiveCurrency = _currency.isNotEmpty ? _currency : accountCurrency;
    final symbol = currencyInfo(effectiveCurrency).symbol;

    final parsedInput =
        double.tryParse(_amtCtrl.text.trim().replaceAll(',', '.'));
    final showConversion = _currency.isNotEmpty &&
        _currency != accountCurrency &&
        app.exchangeRates.isNotEmpty;
    final convertedPreview = showConversion && parsedInput != null
        ? app.convertBetween(parsedInput, _currency, accountCurrency)
        : null;

    final amountInvalid = _submitted && (parsedInput ?? 0) <= 0;
    final accountInvalid = _submitted && _accountId == null;
    final categoryInvalid = _submitted && _categoryId == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _screenTitle(),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: () {
            AppHaptics.tap(context, HapticStrength.light);
            _submit();
          },
          icon: Icon(isEdit ? Icons.save_outlined : Icons.check_rounded),
          label: Text(isEdit ? 'Salvar alterações' : 'Salvar lançamento'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _TypeSelector(
              type: _type,
              onChanged: _setType,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: _type == 'expense'
                    ? cs.errorContainer.withValues(alpha: 0.32)
                    : cs.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Valor',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        symbol,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _amtCtrl,
                          autofocus: !isEdit,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: '0,00',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                          onChanged: (_) => setState(() {
                            _submitted = false;
                          }),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showCurrencyPicker(
                            context,
                            current: effectiveCurrency,
                          );
                          if (picked != null) {
                            setState(() => _currency = picked);
                          }
                        },
                        icon: const Icon(Icons.expand_more_rounded, size: 18),
                        iconAlignment: IconAlignment.end,
                        label: Text(
                          effectiveCurrency,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                  if (amountInvalid) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Informe um valor maior que zero.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (convertedPreview != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: cs.surface.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.swap_horiz_rounded,
                            size: 17,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Na conta: ${formatAmount(convertedPreview, accountCurrency)}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _descCtrl,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Descrição',
                hintText: 'Ex.: almoço, mercado, internet...',
                prefixIcon: const Icon(Icons.edit_note_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const _SectionTitle(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Conta',
              subtitle: 'De onde saiu o dinheiro',
            ),
            const SizedBox(height: 10),
            AccountCardPicker(
              accounts: accounts,
              selectedId: _accountId,
              onSelected: _onAccountSelected,
            ),
            if (accountInvalid) ...[
              const SizedBox(height: 8),
              Text(
                'Escolha uma conta.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 22),
            const _SectionTitle(
              icon: Icons.category_outlined,
              title: 'Categoria',
              subtitle: 'Como este lançamento deve ser classificado',
            ),
            const SizedBox(height: 10),
            CategoryChipPicker(
              categories: cats,
              selectedId: _categoryId,
              onSelected: (id) => setState(() => _categoryId = id),
            ),
            if (categoryInvalid) ...[
              const SizedBox(height: 8),
              Text(
                'Escolha uma categoria.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 22),
            const _SectionTitle(
              icon: Icons.event_outlined,
              title: 'Data',
              subtitle: 'Quando o lançamento aconteceu',
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month_rounded, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        DateFormat('dd/MM/yyyy').format(_date),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              minLines: 2,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Observação (opcional)',
                hintText: 'Algum detalhe que você queira lembrar depois',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 38),
                  child: Icon(Icons.sticky_note_2_outlined),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeSelector extends StatelessWidget {
  final String type;
  final ValueChanged<String> onChanged;

  const _TypeSelector({required this.type, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TypeButton(
              selected: type == 'expense',
              icon: Icons.arrow_upward_rounded,
              label: 'Despesa',
              selectedColor: cs.error,
              onTap: () => onChanged('expense'),
            ),
          ),
          Expanded(
            child: _TypeButton(
              selected: type == 'income',
              icon: Icons.arrow_downward_rounded,
              label: 'Receita',
              selectedColor: const Color(0xFF2E7D32),
              onTap: () => onChanged('income'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final Color selectedColor;
  final VoidCallback onTap;

  const _TypeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.selectedColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: selected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? Colors.white : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 19, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
