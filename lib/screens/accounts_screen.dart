import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import '../widgets/shared_widgets.dart' show showCurrencyPicker;
import 'card_invoice_screen.dart';

class AccountsScreen extends StatelessWidget {
  const AccountsScreen({super.key});

  static void openSheet(
    BuildContext context, {
    Account? existing,
    bool isCard = false,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _AccountEditor(
        existing: existing,
        cardMode:
            isCard || existing?.type == 'credit' || existing?.type == 'debit',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final accounts = app.accounts
        .where((a) => a.type != 'credit' && a.type != 'debit')
        .toList();
    final cards = app.accounts
        .where((a) => a.type == 'credit' || a.type == 'debit')
        .toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Contas e cartões',
              style: TextStyle(fontWeight: FontWeight.w900)),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Saldo total',
                      style: Theme.of(context).textTheme.labelSmall),
                  Text(
                    formatAmount(app.totalBalanceAll, app.settings.currency),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Contas'),
              Tab(text: 'Cartões'),
            ],
          ),
        ),
        floatingActionButton: Padding(
          padding: const EdgeInsets.only(bottom: 76),
          child: FloatingActionButton.extended(
            onPressed: () => _chooseAddType(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Adicionar'),
          ),
        ),
        body: TabBarView(
          children: [
            _AccountsList(accounts: accounts),
            _CardsList(cards: cards),
          ],
        ),
      ),
    );
  }

  static Future<void> _chooseAddType(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text('O que você quer adicionar?',
                    style: TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(
                    'Separe contas do dia a dia e cartões de crédito/débito.'),
              ),
              ListTile(
                leading: const CircleAvatar(
                    child: Icon(Icons.account_balance_wallet_outlined)),
                title: const Text('Conta',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Banco, dinheiro, poupança ou carteira'),
                onTap: () => Navigator.pop(sheetContext, 'account'),
              ),
              ListTile(
                leading:
                    const CircleAvatar(child: Icon(Icons.credit_card_rounded)),
                title: const Text('Cartão',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Crédito ou débito com limite e fatura'),
                onTap: () => Navigator.pop(sheetContext, 'card'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!context.mounted || result == null) return;
    openSheet(context, isCard: result == 'card');
  }
}

class _AccountsList extends StatelessWidget {
  final List<Account> accounts;

  const _AccountsList({required this.accounts});

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return const _EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Nenhuma conta cadastrada',
        subtitle:
            'Adicione onde seu dinheiro fica: banco, carteira, dinheiro ou poupança.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 150),
      itemCount: accounts.length,
      itemBuilder: (_, index) => _AccountTile(account: accounts[index]),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final Account account;

  const _AccountTile({required this.account});

  String _typeLabel() => switch (account.type) {
        'bank' => 'Banco',
        'cash' => 'Dinheiro',
        'savings' => 'Poupança',
        'wallet' => 'Carteira eletrônica',
        'gold' => 'Ouro / ativo',
        _ => 'Conta',
      };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final color = Color(account.colorValue);
    final balance = account.balance;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: .15),
          child: Icon(_accountIcon(account.type), color: color),
        ),
        title: Text(account.name,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text([
          _typeLabel(),
          account.currency,
          if (account.excludeFromTotal) 'fora do saldo total',
        ].join(' • ')),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatAmount(balance, account.currency),
              style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color:
                      balance < 0 ? Theme.of(context).colorScheme.error : null),
            ),
            Text(
              '${app.getAccountTransactions(account.id).length} lançamento${app.getAccountTransactions(account.id).length == 1 ? '' : 's'}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        onTap: () => AccountsScreen.openSheet(context, existing: account),
        onLongPress: () => _confirmDelete(context, account),
      ),
    );
  }
}

class _CardsList extends StatelessWidget {
  final List<Account> cards;

  const _CardsList({required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return const _EmptyState(
        icon: Icons.credit_card_off_outlined,
        title: 'Nenhum cartão cadastrado',
        subtitle:
            'Cadastre o cartão com limite, fechamento e vencimento para acompanhar a fatura.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 150),
      itemCount: cards.length,
      itemBuilder: (_, index) => _CardTile(card: cards[index]),
    );
  }
}

class _CardTile extends StatelessWidget {
  final Account card;

  const _CardTile({required this.card});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final color = Color(card.colorValue);
    final used = card.type == 'credit' ? card.balance.abs() : 0.0;
    final available = card.creditLimit == null
        ? null
        : (card.creditLimit! - used).clamp(0.0, double.infinity).toDouble();
    final linked = card.linkedAccountId == null
        ? null
        : app.accountById(card.linkedAccountId!);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: card.type == 'credit'
            ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => CardInvoiceScreen(cardId: card.id)),
                )
            : () =>
                AccountsScreen.openSheet(context, existing: card, isCard: true),
        onLongPress: () => _confirmDelete(context, card),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: .15),
                    child: Icon(Icons.credit_card_rounded, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(card.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16)),
                        Text(
                          card.type == 'credit'
                              ? 'Cartão de crédito'
                              : 'Cartão de débito',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar cartão',
                    onPressed: () => AccountsScreen.openSheet(context,
                        existing: card, isCard: true),
                    icon: const Icon(Icons.edit_outlined),
                  ),
                ],
              ),
              if (card.type == 'credit') ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                        child: _CardStat(
                            label: 'Usado',
                            value: formatAmount(used, card.currency))),
                    Expanded(
                        child: _CardStat(
                            label: 'Limite livre',
                            value: available == null
                                ? 'Não definido'
                                : formatAmount(available, card.currency))),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Tag(
                        text: card.statementDay == null
                            ? 'Fechamento não definido'
                            : 'Fecha dia ${card.statementDay}'),
                    _Tag(
                        text: card.dueDay == null
                            ? 'Vencimento não definido'
                            : 'Vence dia ${card.dueDay}'),
                    if (linked != null) _Tag(text: 'Paga por ${linked.name}'),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 12),
                Text('Saldo ${formatAmount(card.balance, card.currency)}'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  final String label;
  final String value;

  const _CardStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  final String text;

  const _Tag({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

Future<void> _confirmDelete(BuildContext context, Account account) async {
  final app = context.read<AppProvider>();
  if (app.transactions.any((t) => t.accountId == account.id) ||
      app.recurring.any((r) => r.accountId == account.id) ||
      app.accounts.any((a) => a.linkedAccountId == account.id) ||
      app.savingsContributions.any((c) => c.accountId == account.id)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Esta conta possui vínculos. Realoque os lançamentos, recorrentes e cartões antes de excluir. Você também pode ocultá-la do saldo total na edição.')));
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Excluir conta?'),
      content: Text(
          'Excluir “${account.name}” também pode remover lançamentos vinculados a ela.'),
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
  if (confirmed != true || !context.mounted) return;
  await context.read<AppProvider>().deleteAccount(account.id);
}

IconData _accountIcon(String type) => switch (type) {
      'cash' => Icons.payments_outlined,
      'savings' => Icons.savings_outlined,
      'wallet' => Icons.account_balance_wallet_outlined,
      'gold' => Icons.diamond_outlined,
      'credit' => Icons.credit_card_outlined,
      'debit' => Icons.credit_card_outlined,
      _ => Icons.account_balance_outlined,
    };

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 64, color: cs.onSurfaceVariant.withValues(alpha: .35)),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _AccountEditor extends StatefulWidget {
  final Account? existing;
  final bool cardMode;

  const _AccountEditor({this.existing, required this.cardMode});

  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  final _limitCtrl = TextEditingController();
  final _statementCtrl = TextEditingController();
  final _dueCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _last4Ctrl = TextEditingController();
  final _expiryCtrl = TextEditingController();

  late String _type;
  late String _currency;
  int _color = 0xFF6750A4;
  bool _excludeFromTotal = false;
  String? _linkedAccountId;
  bool _submitted = false;
  bool _saving = false;

  bool get isEdit => widget.existing != null;
  bool get isCard => widget.cardMode;
  bool get isCredit => _type == 'credit';

  static const _colors = [
    0xFF6750A4,
    0xFF1565C0,
    0xFF2E7D32,
    0xFFE65100,
    0xFF00897B,
    0xFFC62828,
    0xFF37474F,
    0xFF7D5260,
  ];

  @override
  void initState() {
    super.initState();
    final app = context.read<AppProvider>();
    _type = widget.cardMode ? 'credit' : 'bank';
    _currency = app.settings.currency;
    final existing = widget.existing;
    if (existing != null) {
      _nameCtrl.text = existing.name;
      _balanceCtrl.text =
          (existing.type == 'credit' ? -existing.balance : existing.balance)
              .toStringAsFixed(2)
              .replaceAll('.', ',');
      _type = existing.type;
      _currency = existing.currency;
      _color = existing.colorValue;
      _excludeFromTotal = existing.excludeFromTotal;
      _linkedAccountId = existing.linkedAccountId;
      _limitCtrl.text =
          existing.creditLimit?.toStringAsFixed(2).replaceAll('.', ',') ?? '';
      _statementCtrl.text = existing.statementDay?.toString() ?? '';
      _dueCtrl.text = existing.dueDay?.toString() ?? '';
      _holderCtrl.text = existing.cardHolderName ?? '';
      _last4Ctrl.text = existing.cardNumberLast4 ?? '';
      _expiryCtrl.text = existing.cardExpiry ?? '';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    _limitCtrl.dispose();
    _statementCtrl.dispose();
    _dueCtrl.dispose();
    _holderCtrl.dispose();
    _last4Ctrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final name = _nameCtrl.text.trim();
    final enteredBalance = parseMoney(_balanceCtrl.text) ?? 0;
    final balance = isCredit ? -enteredBalance : enteredBalance;
    final limit = parseMoney(_limitCtrl.text);
    final statement = int.tryParse(_statementCtrl.text.trim());
    final due = int.tryParse(_dueCtrl.text.trim());

    String? error;
    if (name.isEmpty) error = 'Informe o nome da conta.';
    if (_balanceCtrl.text.trim().isNotEmpty &&
        parseMoney(_balanceCtrl.text) == null)
      error = 'Informe um saldo válido, como 1.234,56.';
    if (isCredit &&
        _limitCtrl.text.trim().isNotEmpty &&
        (limit == null || limit < 0)) error = 'Informe um limite válido.';
    if (isCredit &&
        _statementCtrl.text.trim().isNotEmpty &&
        (statement == null || statement < 1 || statement > 31))
      error = 'Informe o fechamento entre 1 e 31.';
    if (isCredit &&
        _dueCtrl.text.trim().isNotEmpty &&
        (due == null || due < 1 || due > 31))
      error = 'Informe o vencimento entre 1 e 31.';
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    if (isCredit && statement != null && (statement < 1 || statement > 31))
      return;
    if (isCredit && due != null && (due < 1 || due > 31)) return;

    setState(() => _saving = true);
    final app = context.read<AppProvider>();
    final existing = widget.existing;
    if (existing != null &&
        existing.currency != _currency &&
        app.getAccountTransactions(existing.id).isNotEmpty) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Crie outra conta para usar uma moeda diferente e preservar o histórico.')));
      return;
    }

    if (existing == null) {
      await app.addAccount(
        Account(
          id: app.newId(),
          name: name,
          type: _type,
          balance: balance,
          currency: _currency,
          colorValue: _color,
          excludeFromTotal: _excludeFromTotal,
          creditLimit: isCredit ? limit : null,
          statementDay: isCredit ? statement : null,
          dueDay: isCredit ? due : null,
          linkedAccountId: isCard ? _linkedAccountId : null,
          cardHolderName: isCard ? _holderCtrl.text.trim() : null,
          cardNumberLast4: isCard ? _last4Ctrl.text.trim() : null,
          cardExpiry: isCard ? _expiryCtrl.text.trim() : null,
        ),
      );
    } else {
      await app.updateAccount(
        existing.copyWith(
          name: name,
          type: _type,
          balance: balance,
          currency: _currency,
          colorValue: _color,
          excludeFromTotal: _excludeFromTotal,
          creditLimit: isCredit ? limit : null,
          statementDay: isCredit ? statement : null,
          dueDay: isCredit ? due : null,
          linkedAccountId: isCard ? _linkedAccountId : null,
          cardHolderName: isCard ? _holderCtrl.text.trim() : null,
          cardNumberLast4: isCard ? _last4Ctrl.text.trim() : null,
          cardExpiry: isCard ? _expiryCtrl.text.trim() : null,
          clearLinkedAccount: isCard && _linkedAccountId == null,
          clearCredit: !isCredit,
        ),
      );
    }

    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final payableAccounts = app.accounts
        .where((a) =>
            a.id != widget.existing?.id && a.type != 'credit' && !a.isGold)
        .toList();
    final statement = int.tryParse(_statementCtrl.text.trim());
    final due = int.tryParse(_dueCtrl.text.trim());

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .92,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit
                          ? (isCard ? 'Editar cartão' : 'Editar conta')
                          : (isCard ? 'Novo cartão' : 'Nova conta'),
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: isCard ? 'Nome do cartão' : 'Nome da conta',
                      hintText: isCard
                          ? 'Ex.: Nubank Ultravioleta'
                          : 'Ex.: Mercado Pago',
                      prefixIcon: const Icon(Icons.label_outline_rounded),
                      errorText: _submitted && _nameCtrl.text.trim().isEmpty
                          ? 'Informe um nome.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Tipo',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: (isCard
                            ? const [
                                (
                                  'credit',
                                  'Crédito',
                                  Icons.credit_card_rounded
                                ),
                                ('debit', 'Débito', Icons.credit_card_outlined),
                              ]
                            : const [
                                (
                                  'bank',
                                  'Banco',
                                  Icons.account_balance_outlined
                                ),
                                ('cash', 'Dinheiro', Icons.payments_outlined),
                                ('savings', 'Poupança', Icons.savings_outlined),
                                (
                                  'wallet',
                                  'Carteira',
                                  Icons.account_balance_wallet_outlined
                                ),
                                ('gold', 'Ouro/ativo', Icons.diamond_outlined),
                              ])
                        .map((option) => ChoiceChip(
                              selected: _type == option.$1,
                              avatar: Icon(option.$3, size: 18),
                              label: Text(option.$2),
                              onSelected: (_) =>
                                  setState(() => _type = option.$1),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.currency_exchange_rounded),
                    title: const Text('Moeda'),
                    subtitle:
                        Text('$_currency • ${currencyInfo(_currency).name}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final picked =
                          await showCurrencyPicker(context, current: _currency);
                      if (picked != null) setState(() => _currency = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _balanceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: InputDecoration(
                      labelText: isCredit
                          ? 'Valor em aberto no cartão'
                          : 'Saldo inicial / atual',
                      prefixText: '${currencyInfo(_currency).symbol} ',
                      helperText: isCredit
                          ? 'Informe a dívida atual. Use valor negativo somente se houver crédito a seu favor.'
                          : 'Use o saldo real desta conta para começar o controle sem reconstruir todo o passado.',
                    ),
                  ),
                  if (isCredit) ...[
                    const SizedBox(height: 14),
                    Text('Fatura',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _limitCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Limite do cartão',
                        prefixText: '${currencyInfo(_currency).symbol} ',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _statementCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Dia de fechamento',
                              hintText: 'Ex.: 20',
                              errorText: _submitted &&
                                      statement != null &&
                                      (statement < 1 || statement > 31)
                                  ? 'Use 1 a 31'
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: _dueCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Dia de vencimento',
                              hintText: 'Ex.: 27',
                              errorText: _submitted &&
                                      due != null &&
                                      (due < 1 || due > 31)
                                  ? 'Use 1 a 31'
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String?>(
                      isExpanded: true,
                      initialValue:
                          payableAccounts.any((a) => a.id == _linkedAccountId)
                              ? _linkedAccountId
                              : null,
                      decoration: const InputDecoration(
                        labelText: 'Conta padrão para pagar a fatura',
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Nenhuma conta vinculada')),
                        ...payableAccounts.map(
                          (a) => DropdownMenuItem<String?>(
                              value: a.id, child: Text(a.name)),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _linkedAccountId = value),
                    ),
                  ],
                  if (isCard) ...[
                    const SizedBox(height: 16),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('Detalhes opcionais',
                          style: TextStyle(fontWeight: FontWeight.w800)),
                      children: [
                        TextField(
                          controller: _holderCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Nome impresso no cartão'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _last4Ctrl,
                                maxLength: 4,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                    labelText: 'Últimos 4 dígitos',
                                    counterText: ''),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _expiryCtrl,
                                maxLength: 5,
                                keyboardType: TextInputType.datetime,
                                decoration: const InputDecoration(
                                    labelText: 'Validade MM/AA',
                                    counterText: ''),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  if (!isCredit) ...[
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Não incluir no saldo total'),
                      subtitle: const Text(
                          'Útil para contas separadas, valores de terceiros ou controles auxiliares.'),
                      value: _excludeFromTotal,
                      onChanged: (value) =>
                          setState(() => _excludeFromTotal = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text('Cor',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _colors.map((value) {
                      final selected = _color == value;
                      return GestureDetector(
                        onTap: () => setState(() => _color = value),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Color(value),
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(color: cs.onSurface, width: 3)
                                : null,
                          ),
                          child: selected
                              ? const Icon(Icons.check_rounded,
                                  color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_rounded),
                label: Text(isEdit
                    ? 'Salvar alterações'
                    : (isCard ? 'Salvar cartão' : 'Salvar conta')),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
