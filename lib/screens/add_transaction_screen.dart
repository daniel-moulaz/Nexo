import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import '../widgets/shared_widgets.dart' show showCurrencyPicker;
import 'transfer_screen.dart';
import '../services/entry_defaults.dart';

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
  final _amountCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _installmentCurrentCtrl = TextEditingController();
  final _installmentTotalCtrl = TextEditingController();

  late String _type;
  String? _accountId;
  String? _categoryId;
  DateTime _date = DateTime.now();
  String _currency = '';

  String _status = 'paid';
  DateTime? _dueDate;
  String _subcategory = '';
  String _expenseClass = 'normal';
  bool _excludeFromSpending = false;
  bool _isInstallment = false;
  String _source = 'manual';

  bool _submitted = false;
  bool _saving = false;
  bool _duplicateAccepted = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _type = widget.existing?.type ?? widget.initialType;
    final app = context.read<AppProvider>();
    final accounts = app.accounts.where((a) => !a.isGold).toList();
    if (accounts.isNotEmpty) {
      final recent = EntryDefaults.recentAccount(
              accounts, app.transactions, app.transactionMetadata, _type) ??
          accounts.first;
      _accountId = recent.id;
      _currency = recent.currency;
    }
    _selectFirstCategory(app, _type);

    final existing = widget.existing;
    if (existing != null) {
      _amountCtrl.text =
          existing.amount.toStringAsFixed(2).replaceAll('.', ',');
      _descriptionCtrl.text = existing.description;
      _noteCtrl.text = existing.note;
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

  void _selectFirstCategory(AppProvider app, String type) {
    final categories = app.categories.where((c) => c.type == type).toList();
    _categoryId = categories.firstOrNull?.id;
  }

  Future<void> _loadMetadata(String id) async {
    final metadata = await TransactionMetadataService.instance.getFor(id);
    if (!mounted) return;
    setState(() {
      _status = metadata.status;
      _dueDate = metadata.dueDate;
      _subcategory = metadata.subcategory;
      _expenseClass = metadata.expenseClass;
      _excludeFromSpending = metadata.excludeFromSpending;
      _source = metadata.source;
      if (metadata.installmentCurrent != null &&
          metadata.installmentTotal != null) {
        _isInstallment = true;
        _installmentCurrentCtrl.text = '${metadata.installmentCurrent}';
        _installmentTotalCtrl.text = '${metadata.installmentTotal}';
      }
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
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

  List<String> _subcategories(String? categoryId) {
    const values = <String, List<String>>{
      'food_exp': ['Mercado', 'Lanche', 'Restaurante', 'Delivery'],
      'transport': [
        'Combustível',
        'Transporte por app',
        'Ônibus/Metrô',
        'Manutenção',
        'Estacionamento',
      ],
      'shopping': ['Roupas', 'Eletrônicos', 'Casa', 'Pessoal', 'Outros'],
      'bills': [
        'Água',
        'Luz',
        'Internet',
        'Telefone',
        'Assinaturas',
        'Aluguel'
      ],
      'health': ['Farmácia', 'Consulta', 'Exames', 'Academia'],
      'entertainment': ['Streaming', 'Cinema', 'Jogos', 'Passeio'],
      'education': ['Faculdade', 'Cursos', 'Livros', 'Material'],
      'other_exp': ['Outros'],
      'salary': ['Salário'],
      'freelance': ['Freelance', 'Bônus', 'Reembolso', 'Outros'],
      'business': ['Negócios'],
      'investment': ['Rendimentos', 'Dividendos', 'Juros'],
      'gift': ['Presente', 'Doação recebida'],
    };
    return values[categoryId] ?? const [];
  }

  void _setType(String type) {
    if (type == 'transfer') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TransferScreen()),
      );
      return;
    }
    final app = context.read<AppProvider>();
    setState(() {
      _type = type;
      _selectFirstCategory(app, type);
      _subcategory = '';
      _status = 'paid';
      _dueDate = null;
      if (type == 'income') {
        _expenseClass = 'normal';
        _excludeFromSpending = false;
        _isInstallment = false;
      }
    });
  }

  Future<bool> _confirmDuplicate(List<AppTransaction> duplicates) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Possível duplicidade'),
        content: Text(
          duplicates.length == 1
              ? 'Já existe um lançamento parecido. Deseja salvar mesmo assim?'
              : 'Existem ${duplicates.length} lançamentos parecidos. Deseja salvar mesmo assim?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Revisar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Salvar mesmo assim'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final amount = parseMoney(_amountCtrl.text);
    final currentInstallment =
        int.tryParse(_installmentCurrentCtrl.text.trim());
    final totalInstallments = int.tryParse(_installmentTotalCtrl.text.trim());
    final installmentValid = !_isInstallment ||
        (currentInstallment != null &&
            totalInstallments != null &&
            currentInstallment > 0 &&
            totalInstallments > 0 &&
            currentInstallment <= totalInstallments);

    if (amount == null ||
        amount <= 0 ||
        _accountId == null ||
        _categoryId == null ||
        !installmentValid) {
      final errors = <String>[
        if (amount == null || amount <= 0) 'valor',
        if (_accountId == null) 'conta',
        if (_categoryId == null) 'categoria',
        if (!installmentValid) 'parcela atual e total de parcelas',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Revise: ${errors.join(', ')}.')));
      return;
    }

    final app = context.read<AppProvider>();
    final account = app.accountById(_accountId!);
    if (account == null) return;
    final txCurrency = _currency.isEmpty ? account.currency : _currency;
    final storedCurrency = txCurrency == account.currency ? '' : txCurrency;
    final id = widget.existing?.id ?? app.newId();

    final transaction = AppTransaction(
      id: id,
      type: _type,
      amount: amount,
      description: _descriptionCtrl.text.trim(),
      accountId: _accountId!,
      categoryId: _categoryId!,
      date: _date,
      note: _noteCtrl.text.trim(),
      currency: storedCurrency,
    );

    final duplicates = app.findPossibleDuplicates(
      transaction,
      excludeId: widget.existing?.id,
    );
    if (duplicates.isNotEmpty && !_duplicateAccepted) {
      if (!await _confirmDuplicate(duplicates)) return;
      _duplicateAccepted = true;
    }

    setState(() => _saving = true);
    final metadata = TransactionMetadata(
      transactionId: id,
      subcategory: _subcategory,
      status: _status,
      dueDate: _status == 'pending' ? (_dueDate ?? _date) : null,
      expenseClass: _type == 'expense' ? _expenseClass : 'normal',
      excludeFromSpending: _type == 'expense' && _excludeFromSpending,
      installmentCurrent:
          _type == 'expense' && _isInstallment ? currentInstallment : null,
      installmentTotal:
          _type == 'expense' && _isInstallment ? totalInstallments : null,
      source: _source,
      affectsBalance: isEdit
          ? (await TransactionMetadataService.instance.getFor(id))
              .affectsBalance
          : true,
    );
    try {
      if (isEdit) {
        await app.updateTransaction(transaction, widget.existing!,
            metadata: metadata);
      } else {
        await app.addTransaction(transaction, metadata: metadata);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Não foi possível salvar. Revise os campos. Para alterar uma transferência, exclua e registre novamente.')));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Excluir lançamento?'),
        content: const Text(
            'Essa ação desfaz o efeito no saldo. Em transferências ou pagamentos de fatura, os dois lados serão excluídos juntos. Em compras parceladas, só esta parcela será excluída.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final app = context.read<AppProvider>();
    await app.deleteTransaction(existing.id);
    await TransactionMetadataService.instance.delete(existing.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts = app.accounts.where((a) => !a.isGold).toList();
    final categories = app.categories.where((c) => c.type == _type).toList();
    final subcategories = _subcategories(_categoryId);
    final amount = parseMoney(_amountCtrl.text);
    final currentInstallment =
        int.tryParse(_installmentCurrentCtrl.text.trim());
    final totalInstallments = int.tryParse(_installmentTotalCtrl.text.trim());

    final selectedAccount = app.accountById(_accountId ?? '');
    final effectiveCurrency = _currency.isNotEmpty
        ? _currency
        : (selectedAccount?.currency ?? app.settings.currency);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEdit
              ? (_type == 'income' ? 'Editar receita' : 'Editar despesa')
              : (_type == 'income' ? 'Nova receita' : 'Nova despesa'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'Excluir lançamento',
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(isEdit ? 'Salvar alterações' : 'Salvar lançamento'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final type in ['expense', 'income', if (!isEdit) 'transfer'])
              ChoiceChip(
                  label: Text(const {
                    'expense': 'Despesa',
                    'income': 'Receita',
                    'transfer': 'Transferência'
                  }[type]!),
                  selected: _type == type,
                  onSelected: (_) => _setType(type)),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _type == 'expense'
                  ? cs.errorContainer.withValues(alpha: .28)
                  : cs.primaryContainer.withValues(alpha: .48),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Valor', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      currencyInfo(effectiveCurrency).symbol,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amountCtrl,
                        autofocus: !isEdit,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          hintText: '0,00',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                        onChanged: (_) => setState(() {}),
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
                      icon: const Icon(Icons.expand_more_rounded),
                      iconAlignment: IconAlignment.end,
                      label: Text(effectiveCurrency),
                    ),
                  ],
                ),
                if (_submitted && (amount == null || amount <= 0))
                  Text(
                    'Informe um valor maior que zero.',
                    style:
                        TextStyle(color: cs.error, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _descriptionCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Descrição',
              hintText: _type == 'income'
                  ? 'Ex.: salário, reembolso, freelance...'
                  : 'Ex.: mercado, almoço, internet...',
              prefixIcon: const Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.account_balance_wallet_outlined,
            title: 'Conta',
            subtitle: _type == 'income'
                ? 'Onde o dinheiro entrou'
                : 'De onde saiu o dinheiro',
          ),
          const SizedBox(height: 8),
          if (accounts.isEmpty)
            _WarningCard(
              text: 'Cadastre uma conta antes de salvar um lançamento.',
              icon: Icons.account_balance_wallet_outlined,
            )
          else
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue:
                  accounts.any((a) => a.id == _accountId) ? _accountId : null,
              decoration: InputDecoration(
                labelText: 'Conta ou cartão',
                errorText: _submitted && _accountId == null
                    ? 'Escolha uma conta.'
                    : null,
              ),
              items: accounts.map((account) {
                final type = switch (account.type) {
                  'bank' => 'Banco',
                  'cash' => 'Dinheiro',
                  'savings' => 'Poupança',
                  'wallet' => 'Carteira',
                  'credit' => 'Cartão de crédito',
                  'debit' => 'Cartão de débito',
                  _ => 'Conta',
                };
                return DropdownMenuItem(
                  value: account.id,
                  child: Text('${account.name} • $type'),
                );
              }).toList(),
              onChanged: (id) {
                if (id == null) return;
                final account = app.accountById(id);
                setState(() {
                  _accountId = id;
                  _currency = account?.currency ?? app.settings.currency;
                });
              },
            ),
          const SizedBox(height: 20),
          const _SectionTitle(
            icon: Icons.category_outlined,
            title: 'Categoria',
            subtitle: 'Organize para entender para onde o dinheiro vai',
          ),
          const SizedBox(height: 8),
          if (categories.isEmpty)
            _WarningCard(
              text: _type == 'income'
                  ? 'Cadastre uma categoria de receita.'
                  : 'Cadastre uma categoria de despesa.',
              icon: Icons.category_outlined,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: categories.map((category) {
                return ChoiceChip(
                  selected: _categoryId == category.id,
                  label: Text(_categoryLabel(category)),
                  avatar: CircleAvatar(
                    radius: 4,
                    backgroundColor: Color(category.colorValue),
                  ),
                  onSelected: (_) {
                    setState(() {
                      _categoryId = category.id;
                      if (!_subcategories(category.id).contains(_subcategory)) {
                        _subcategory = '';
                      }
                    });
                  },
                );
              }).toList(),
            ),
          if (_submitted && _categoryId == null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Escolha uma categoria.',
                  style: TextStyle(color: cs.error)),
            ),
          if (subcategories.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Subcategoria',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: subcategories.map((value) {
                return ChoiceChip(
                  label: Text(value),
                  selected: _subcategory == value,
                  onSelected: (selected) {
                    setState(() => _subcategory = selected ? value : '');
                  },
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 20),
          _SectionTitle(
            icon: Icons.fact_check_outlined,
            title: _type == 'income'
                ? 'Situação da receita'
                : 'Situação da despesa',
            subtitle: _type == 'income'
                ? 'Separe o que já recebeu do que ainda está previsto'
                : 'Separe o que já foi pago do que ainda está pendente',
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'paid',
                label: Text(_type == 'income' ? 'Recebida' : 'Paga'),
                icon: const Icon(Icons.check_circle_outline_rounded),
              ),
              ButtonSegment(
                value: 'pending',
                label: Text(_type == 'income' ? 'Prevista' : 'Pendente'),
                icon: const Icon(Icons.schedule_rounded),
              ),
            ],
            selected: {_status},
            onSelectionChanged: (selection) {
              setState(() {
                _status = selection.first;
                if (_status == 'pending') _dueDate ??= _date;
              });
            },
          ),
          if (_status == 'pending') ...[
            const SizedBox(height: 10),
            _DateTile(
              title: _type == 'income' ? 'Data prevista' : 'Vencimento',
              date: _dueDate ?? _date,
              icon: Icons.event_outlined,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dueDate ?? _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                  cancelText: 'Cancelar',
                  confirmText: 'Selecionar',
                );
                if (picked != null) setState(() => _dueDate = picked);
              },
            ),
          ],
          if (_type == 'expense') ...[
            const SizedBox(height: 20),
            const _SectionTitle(
              icon: Icons.tune_rounded,
              title: 'Classificação',
              subtitle: 'Separe o custo normal dos gastos fora da rotina',
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'normal', label: Text('Normal')),
                ButtonSegment(
                    value: 'extraordinary', label: Text('Extraordinária')),
              ],
              selected: {_expenseClass},
              onSelectionChanged: (selection) {
                setState(() => _expenseClass = selection.first);
              },
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _excludeFromSpending,
              onChanged: (value) =>
                  setState(() => _excludeFromSpending = value),
              title: const Text('Não contar como gasto'),
              subtitle: const Text(
                'Use para movimentos neutros, ajustes, reserva ou casos especiais. Para transferências entre contas, prefira “Transferir”.',
              ),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _isInstallment,
              onChanged: (value) => setState(() => _isInstallment = value),
              title: const Text('Compra parcelada'),
              subtitle: const Text(
                  'Informe o valor de cada parcela e a parcela atual (ex.: 3 de 12). As próximas serão criadas mensalmente. Ao editar ou excluir, só esta parcela será alterada.'),
            ),
            if (_isInstallment) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _installmentCurrentCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Parcela atual'),
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
                      decoration: const InputDecoration(labelText: 'Total'),
                    ),
                  ),
                ],
              ),
              if (_submitted &&
                  (currentInstallment == null ||
                      totalInstallments == null ||
                      currentInstallment <= 0 ||
                      totalInstallments <= 0 ||
                      currentInstallment > totalInstallments))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Informe uma parcela válida, como 3 de 12.',
                    style: TextStyle(color: cs.error),
                  ),
                ),
            ],
          ],
          const SizedBox(height: 20),
          const _SectionTitle(
            icon: Icons.calendar_month_outlined,
            title: 'Data do lançamento',
            subtitle: 'Quando a movimentação aconteceu',
          ),
          const SizedBox(height: 8),
          _DateTile(
            title: 'Data',
            date: _date,
            icon: Icons.event_available_outlined,
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _date,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                cancelText: 'Cancelar',
                confirmText: 'Selecionar',
              );
              if (picked != null) {
                setState(() {
                  _date = picked;
                  if (_status == 'pending' && _dueDate == null)
                    _dueDate = picked;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteCtrl,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Observação (opcional)',
              prefixIcon: Icon(Icons.sticky_note_2_outlined),
            ),
          ),
        ],
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
    final cs = Theme.of(context).colorScheme;
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _DateTile extends StatelessWidget {
  final String title;
  final DateTime date;
  final IconData icon;
  final VoidCallback onTap;

  const _DateTile({
    required this.title,
    required this.date,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                  Text(title, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(ptDate(date),
                      style: const TextStyle(fontWeight: FontWeight.w900)),
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

class _WarningCard extends StatelessWidget {
  final String text;
  final IconData icon;

  const _WarningCard({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: .35),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: cs.error),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
