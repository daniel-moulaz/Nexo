import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import '../utils/haptics.dart';
import '../widgets/shared_widgets.dart';

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
  final _installmentCurrentCtrl = TextEditingController();
  final _installmentTotalCtrl = TextEditingController();

  bool _submitted = false;
  bool _dupeWarningDismissed = false;

  late String _type = widget.existing?.type ?? widget.initialType;
  String? _accountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  String _currency = '';

  String _status = 'paid';
  String _subcategory = '';
  DateTime? _dueDate;
  String _expenseClass = 'normal';
  bool _excludeFromSpending = false;
  bool _isInstallment = false;
  String _source = 'manual';

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    final accounts = app.accounts.where((a) => !a.isGold).toList();

    if (accounts.isNotEmpty) {
      _accountId = accounts.first.id;
      _currency = accounts.first.currency;
    }

    final cats = app.categories.where((c) => c.type == _type).toList();
    if (cats.isNotEmpty) _categoryId = cats.first.id;

    final existing = widget.existing;
    if (existing != null) {
      _amtCtrl.text = existing.amount.toStringAsFixed(2).replaceAll('.', ',');
      _descCtrl.text = existing.description;
      _noteCtrl.text = existing.note;
      _type = existing.type;
      _accountId = existing.accountId;
      _categoryId = existing.categoryId;
      _date = existing.date;
      final account = app.accountById(existing.accountId);
      _currency = existing.currency.isNotEmpty
          ? existing.currency
          : (account?.currency ?? app.settings.currency);
      _loadMetadata(existing.id);
    }
  }

  Future<void> _loadMetadata(String transactionId) async {
    final metadata =
        await TransactionMetadataService.instance.getFor(transactionId);
    if (!mounted) return;
    setState(() {
      _status = metadata.status;
      _subcategory = metadata.subcategory;
      _dueDate = metadata.dueDate;
      _expenseClass = metadata.expenseClass;
      _excludeFromSpending = metadata.excludeFromSpending;
      _source = metadata.source;
      if (metadata.installmentCurrent != null &&
          metadata.installmentTotal != null) {
        _isInstallment = true;
        _installmentCurrentCtrl.text = metadata.installmentCurrent.toString();
        _installmentTotalCtrl.text = metadata.installmentTotal.toString();
      }
    });
  }

  @override
  void dispose() {
    _amtCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    _installmentCurrentCtrl.dispose();
    _installmentTotalCtrl.dispose();
    super.dispose();
  }

  String _categoryLabel(AppCategory category) {
    const labels = {
      'food_exp': 'Alimentação',
      'transport': 'Transporte',
      'shopping': 'Compras',
      'bills': 'Moradia & Contas',
      'health': 'Saúde',
      'entertainment': 'Lazer',
      'education': 'Educação',
      'other_exp': 'Outros',
      'salary': 'Salário',
      'freelance': 'Freelancer',
      'business': 'Negócios',
      'investment': 'Investimentos',
      'gift': 'Presentes',
    };
    return labels[category.id] ?? category.name;
  }

  List<String> _subcategoryOptions(String? categoryId) {
    const options = <String, List<String>>{
      'food_exp': ['Mercado', 'Lanche', 'Restaurante', 'Delivery'],
      'transport': [
        'Combustível',
        'Transporte por app',
        'Ônibus/Metrô',
        'Manutenção',
        'Estacionamento',
      ],
      'shopping': ['Roupas', 'Eletrônicos', 'Casa', 'Pessoal', 'Outros'],
      'bills': ['Água', 'Luz', 'Internet', 'Telefone', 'Assinaturas', 'Aluguel'],
      'health': ['Farmácia', 'Consulta', 'Exames', 'Academia'],
      'entertainment': ['Streaming', 'Cinema', 'Jogos', 'Lazer'],
      'education': ['Faculdade', 'Cursos', 'Livros', 'Material'],
      'other_exp': ['Outros'],
    };
    return options[categoryId] ?? const [];
  }

  void _setType(String type) {
    final app = context.read<AppProvider>();
    final cats = app.categories.where((c) => c.type == type).toList();
    setState(() {
      _type = type;
      _categoryId = cats.isNotEmpty ? cats.first.id : null;
      _subcategory = '';
      if (type != 'expense') {
        _status = 'paid';
        _dueDate = null;
        _expenseClass = 'normal';
        _excludeFromSpending = false;
        _isInstallment = false;
      }
    });
  }

  void _onAccountSelected(String? id) {
    if (id == null) return;
    final app = context.read<AppProvider>();
    final account = app.accountById(id);
    setState(() {
      _accountId = id;
      _currency = account?.currency ?? app.settings.currency;
    });
  }

  void _onCategorySelected(String id) {
    final validSubcategories = _subcategoryOptions(id);
    setState(() {
      _categoryId = id;
      if (!validSubcategories.contains(_subcategory)) _subcategory = '';
    });
  }

  Future<bool?> _showDuplicateWarningDialog(List<AppTransaction> dupes) {
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
                      '• ${formatAmount(d.amount, d.currency)} em ${DateFormat('dd/MM').format(d.date)}${d.description.isNotEmpty ? ' — ${d.description}' : ''}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Voltar'),
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

    int? installmentCurrent;
    int? installmentTotal;
    if (_type == 'expense' && _isInstallment) {
      installmentCurrent = int.tryParse(_installmentCurrentCtrl.text.trim());
      installmentTotal = int.tryParse(_installmentTotalCtrl.text.trim());
      if (installmentCurrent == null ||
          installmentTotal == null ||
          installmentCurrent <= 0 ||
          installmentTotal <= 0 ||
          installmentCurrent > installmentTotal) {
        return;
      }
    }

    final app = context.read<AppProvider>();
    final account = app.accountById(_accountId!);
    final accountCurrency = account?.currency ?? app.settings.currency;
    final storeCurrency = _currency == accountCurrency ? '' : _currency;
    final transactionId = isEdit ? widget.existing!.id : app.newId();

    final targetTx = AppTransaction(
      id: transactionId,
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

    if (_type == 'expense') {
      await TransactionMetadataService.instance.save(
        TransactionMetadata(
          transactionId: transactionId,
          subcategory: _subcategory,
          status: _status,
          dueDate: _status == 'pending' ? (_dueDate ?? _date) : null,
          expenseClass: _expenseClass,
          excludeFromSpending: _excludeFromSpending,
          installmentCurrent: installmentCurrent,
          installmentTotal: installmentTotal,
          source: _source,
        ),
      );
    } else {
      await TransactionMetadataService.instance.delete(transactionId);
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
    final accounts = app.accounts.where((a) => !a.isGold).toList();

    final selectedAccount = app.accountById(_accountId ?? '');
    final accountCurrency = selectedAccount?.currency ?? app.settings.currency;
    final effectiveCurrency = _currency.isNotEmpty ? _currency : accountCurrency;
    final symbol = currencyInfo(effectiveCurrency).symbol;
    final parsedInput =
        double.tryParse(_amtCtrl.text.trim().replaceAll(',', '.'));

    final amountInvalid = _submitted && (parsedInput ?? 0) <= 0;
    final accountInvalid = _submitted && _accountId == null;
    final categoryInvalid = _submitted && _categoryId == null;
    final installmentCurrent = int.tryParse(_installmentCurrentCtrl.text.trim());
    final installmentTotal = int.tryParse(_installmentTotalCtrl.text.trim());
    final installmentInvalid = _submitted &&
        _type == 'expense' &&
        _isInstallment &&
        (installmentCurrent == null ||
            installmentTotal == null ||
            installmentCurrent <= 0 ||
            installmentTotal <= 0 ||
            installmentCurrent > installmentTotal);
    final subcategories = _subcategoryOptions(_categoryId);

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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _TypeSelector(type: _type, onChanged: _setType),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              decoration: BoxDecoration(
                color: _type == 'expense'
                    ? cs.errorContainer.withValues(alpha: 0.32)
                    : cs.primaryContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(24),
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
                          ),
                          onChanged: (_) => setState(() => _submitted = false),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await showCurrencyPicker(
                            context,
                            current: effectiveCurrency,
                          );
                          if (picked != null) setState(() => _currency = picked);
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
            _SectionTitle(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Conta',
              subtitle: _type == 'expense'
                  ? 'De onde saiu o dinheiro'
                  : 'Onde o dinheiro entrou',
            ),
            const SizedBox(height: 10),
            AccountCardPicker(
              accounts: accounts,
              selectedId: _accountId,
              onSelected: _onAccountSelected,
            ),
            if (accountInvalid) ...[
              const SizedBox(height: 8),
              Text('Escolha uma conta.', style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 22),
            const _SectionTitle(
              icon: Icons.category_outlined,
              title: 'Categoria',
              subtitle: 'Como este lançamento deve ser classificado',
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: cats.map((category) {
                final selected = _categoryId == category.id;
                final color = Color(category.colorValue);
                return FilterChip(
                  selected: selected,
                  label: Text(_categoryLabel(category)),
                  avatar: CircleAvatar(backgroundColor: color, radius: 4),
                  onSelected: (_) => _onCategorySelected(category.id),
                );
              }).toList(),
            ),
            if (categoryInvalid) ...[
              const SizedBox(height: 8),
              Text('Escolha uma categoria.', style: TextStyle(color: cs.error)),
            ],
            if (_type == 'expense' && subcategories.isNotEmpty) ...[
              const SizedBox(height: 22),
              const _SectionTitle(
                icon: Icons.subdirectory_arrow_right_rounded,
                title: 'Subcategoria',
                subtitle: 'Detalhe melhor onde esse gasto entrou',
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subcategories.map((item) {
                  return ChoiceChip(
                    label: Text(item),
                    selected: _subcategory == item,
                    onSelected: (selected) {
                      setState(() => _subcategory = selected ? item : '');
                    },
                  );
                }).toList(),
              ),
            ],
            if (_type == 'expense') ...[
              const SizedBox(height: 22),
              const _SectionTitle(
                icon: Icons.fact_check_outlined,
                title: 'Situação',
                subtitle: 'Controle o que já foi pago e o que ainda vence',
              ),
              const SizedBox(height: 10),
              _StatusSelector(
                status: _status,
                onChanged: (value) {
                  setState(() {
                    _status = value;
                    if (value == 'pending') _dueDate ??= _date;
                  });
                },
              ),
              if (_status == 'pending') ...[
                const SizedBox(height: 12),
                _DatePickerTile(
                  icon: Icons.event_busy_outlined,
                  label: 'Vencimento',
                  date: _dueDate ?? _date,
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _dueDate ?? _date,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _dueDate = picked);
                  },
                ),
              ],
              const SizedBox(height: 22),
              const _SectionTitle(
                icon: Icons.tune_rounded,
                title: 'Classificação financeira',
                subtitle: 'Separe custo normal de gastos fora da rotina',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Normal'),
                      selected: _expenseClass == 'normal',
                      onSelected: (_) => setState(() => _expenseClass = 'normal'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Extraordinário'),
                      selected: _expenseClass == 'extraordinary',
                      onSelected: (_) =>
                          setState(() => _expenseClass = 'extraordinary'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _excludeFromSpending,
                onChanged: (value) =>
                    setState(() => _excludeFromSpending = value),
                title: const Text('Não contar como gasto'),
                subtitle: const Text(
                  'Use para transferência, reserva, pagamento de fatura ou outro movimento neutro.',
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _isInstallment,
                onChanged: (value) => setState(() => _isInstallment = value),
                title: const Text('Compra parcelada'),
                subtitle: const Text('Guarde a posição da parcela, ex.: 3 de 12.'),
              ),
              if (_isInstallment) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _installmentCurrentCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Parcela atual',
                          hintText: '3',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: Text('de'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _installmentTotalCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Total',
                          hintText: '12',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (installmentInvalid) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Informe uma parcela válida, por exemplo 3 de 12.',
                    style: TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ],
            const SizedBox(height: 22),
            const _SectionTitle(
              icon: Icons.event_outlined,
              title: 'Data',
              subtitle: 'Quando o lançamento aconteceu',
            ),
            const SizedBox(height: 10),
            _DatePickerTile(
              icon: Icons.calendar_month_rounded,
              label: 'Data do lançamento',
              date: _date,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() {
                    _date = picked;
                    if (_status == 'pending' && _dueDate == null) {
                      _dueDate = picked;
                    }
                  });
                }
              },
            ),
            const SizedBox(height: 22),
            TextField(
              controller: _noteCtrl,
              maxLines: 3,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Observação (opcional)',
                hintText: 'Algum detalhe que você queira lembrar depois',
                alignLabelWithHint: true,
                prefixIcon: const Icon(Icons.sticky_note_2_outlined),
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
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TypeButton(
              selected: type == 'expense',
              icon: Icons.arrow_upward_rounded,
              label: 'Despesa',
              color: cs.error,
              onTap: () => onChanged('expense'),
            ),
          ),
          Expanded(
            child: _TypeButton(
              selected: type == 'income',
              icon: Icons.arrow_downward_rounded,
              label: 'Receita',
              color: Colors.green,
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
  final Color color;
  final VoidCallback onTap;

  const _TypeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.24) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : null, size: 20),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? color : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusSelector extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;

  const _StatusSelector({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatusButton(
            selected: status == 'paid',
            icon: Icons.check_circle_outline_rounded,
            label: 'Pago',
            onTap: () => onChanged('paid'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusButton(
            selected: status == 'pending',
            icon: Icons.schedule_rounded,
            label: 'Pendente',
            onTap: () => onChanged('pending'),
          ),
        ),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _StatusButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
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
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: cs.onPrimaryContainer, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
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

class _DatePickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DatePickerTile({
    required this.icon,
    required this.label,
    required this.date,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(icon, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('dd/MM/yyyy').format(date),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
