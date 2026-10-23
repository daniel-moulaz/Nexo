import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/balance_check.dart';
import '../services/bank_snapshots.dart';
import '../services/pluggy_inbox.dart';
import '../widgets/analysis_widgets.dart';
import '../widgets/nexo_ui.dart';

/// "Conferir com o banco": each Open Finance account against the Nexo
/// account it is linked to, at the moment the bank was read. A difference
/// can be fixed with a neutral balance adjustment (the same as editing the
/// balance in the account screen: neither spending nor income), always
/// after confirmation.
class BalanceCheckScreen extends StatefulWidget {
  const BalanceCheckScreen({super.key, this.remote});

  /// Tests pass a fake; the app uses the signed-in Pluggy connection.
  final PluggyRemote? remote;
  @override
  State<BalanceCheckScreen> createState() => _BalanceCheckScreenState();
}

class _BalanceCheckScreenState extends State<BalanceCheckScreen> {
  List<BankAccountSnapshot>? _accounts;
  String? _error;

  PluggyRemote? get _remote => widget.remote ?? PluggyInbox.instance?.remote;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final remote = _remote;
    if (remote == null) {
      setState(() => _error =
          'Conecte o Open Finance em Sincronizar dispositivos para conferir os saldos.');
      return;
    }
    try {
      final list = await remote.accounts();
      if (mounted) {
        setState(() {
          _accounts = list;
          _error = null;
        });
      }
    } on PluggyUnavailable catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Não foi possível ler os saldos do banco agora.');
      }
    }
  }

  Future<void> _link(BankAccountSnapshot b, String? nexoId) async {
    try {
      await _remote!.link(b.accountId, nexoId);
      // Other screens (invoice, limit) read the shared cache: refresh it now.
      await BankSnapshots.load(force: true);
      await _load();
    } catch (_) {
      if (mounted)
        setState(() => _error = 'Não foi possível salvar o vínculo.');
    }
  }

  Future<void> _adjust(AppProvider app, Account acc, BalanceCheck c) async {
    final diff = c.differenceCents / 100;
    final target = acc.balance + diff;
    final ok = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
                title: const Text('Ajustar o saldo do Nexo?'),
                content: Text(
                    '${acc.name}: de ${analysisMoney(app, acc.balance)} para ${analysisMoney(app, target)}.\n\n'
                    'É um ajuste neutro: não conta como gasto nem como receita, como editar o saldo na conta.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(d, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(d, true),
                      child: const Text('Ajustar')),
                ]));
    if (ok != true || !mounted) return;
    final current = app.accountById(acc.id);
    if (current == null) return;
    await app.updateAccount(current.copyWith(balance: current.balance + diff),
        original: current);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Saldo ajustado. Nada foi contado como gasto ou receita.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    String money(double v) => analysisMoney(app, v);
    final when = DateFormat("dd/MM 'às' HH:mm");
    final list = _accounts;
    // Bank accounts (not cards) linked to the same Nexo account are summed.
    final groups = <String, List<BankAccountSnapshot>>{};
    for (final b in list ?? const <BankAccountSnapshot>[]) {
      final id = b.nexoAccountId;
      if (id != null && !b.isCard) (groups[id] ??= []).add(b);
    }
    groups.removeWhere((_, v) => v.length < 2);
    return Scaffold(
      appBar: AppBar(title: const Text('Conferir com o banco'), actions: [
        IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Text(
                'O banco atualiza o Open Finance uma vez por dia. A comparação usa o saldo do Nexo no mesmo momento da leitura do banco, então lançamentos de depois não contam como diferença.'),
            const SizedBox(height: 12),
            if (_error != null)
              Text(_error!, style: TextStyle(color: cs.error)),
            if (list == null && _error == null) const LinearProgressIndicator(),
            if (list != null && list.isEmpty)
              const Text(
                  'Nenhuma conta do banco ainda. Os saldos aparecem depois da próxima leitura do Open Finance.'),
            for (final g in groups.entries)
              if (app.accountById(g.key) case final acc?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GroupCard(
                      account: acc,
                      banks: g.value,
                      app: app,
                      money: money,
                      when: when,
                      onAdjust: (acc, c) => _adjust(app, acc, c)),
                ),
            for (final b in list ?? const <BankAccountSnapshot>[])
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _BankCard(
                    bank: b,
                    app: app,
                    money: money,
                    when: when,
                    sharedWith: (groups[b.nexoAccountId]?.length ?? 1) - 1,
                    onLink: (id) => _link(b, id),
                    onAdjust: (acc, c) => _adjust(app, acc, c)),
              ),
          ],
        ),
      ),
    );
  }
}

class _BankCard extends StatelessWidget {
  const _BankCard(
      {required this.bank,
      required this.app,
      required this.money,
      required this.when,
      required this.onLink,
      required this.onAdjust,
      this.sharedWith = 0});
  final BankAccountSnapshot bank;
  final int sharedWith;
  final AppProvider app;
  final String Function(double) money;
  final DateFormat when;
  final ValueChanged<String?> onLink;
  final void Function(Account, BalanceCheck) onAdjust;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final choices = app.accounts
        .where((a) => !a.isGold && (a.type == 'credit') == bank.isCard)
        .toList();
    final linked = choices.where((a) => a.id == bank.nexoAccountId).firstOrNull;
    final check = linked == null
        ? null
        : checkBalance(
            account: linked,
            bank: bank,
            transactions: app.transactions,
            metadata: app.transactionMetadata);
    final signed = bank.nexoSignedCents;
    return NexoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(bank.isCard ? Icons.credit_card : Icons.account_balance,
              color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Text('${bank.bank} · ${bank.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 8),
        Text(
            signed == null
                ? 'O banco não informou o saldo.'
                : '${bank.isCard ? 'Dívida no banco' : 'No banco'}: ${money(signed / 100)}',
            style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                fontFeatures: NexoTones.figures)),
        Text(
            bank.bankUpdatedAt == null
                ? 'Data da última movimentação não informada'
                : 'Última movimentação recebida em ${when.format(bank.bankUpdatedAt!)}',
            style: small),
        if (bank.isCard && bank.creditLimitCents != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                'Limite ${money(bank.creditLimitCents! / 100)}'
                '${bank.availableCents == null ? '' : ' · disponível ${money(bank.availableCents! / 100)}'}',
                style: small),
          ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: linked?.id,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Conta no Nexo'),
          items: [
            const DropdownMenuItem<String?>(
                value: null, child: Text('Não vincular')),
            for (final a in choices)
              DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
          ],
          onChanged: onLink,
        ),
        if (sharedWith > 0 && linked != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                'Somada com mais $sharedWith conta(s) do banco em ${linked.name}: a comparação está no total acima.',
                style: small),
          )
        else
          _CheckView(
              linked: linked, check: check, money: money, onAdjust: onAdjust),
      ]),
    );
  }
}

/// The bank against the Nexo at the same moment, with the neutral adjust.
class _CheckView extends StatelessWidget {
  const _CheckView(
      {required this.linked,
      required this.check,
      required this.money,
      required this.onAdjust});
  final Account? linked;
  final BalanceCheck? check;
  final String Function(double) money;
  final void Function(Account, BalanceCheck) onAdjust;

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    final check = this.check, linked = this.linked;
    if (linked == null) return const SizedBox.shrink();
    if (check == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(
            'Não dá para comparar: o banco não informou o saldo ou a moeda é diferente.',
            style: small),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      Text('No Nexo naquele momento: ${money(check.nexoAtBankCents / 100)}'),
      if (check.laterEntries.isNotEmpty)
        Text(
            '${check.laterEntries.length} lançamento(s) depois da leitura do banco ficaram de fora.',
            style: small),
      const SizedBox(height: 8),
      if (check.matches)
        Row(children: [
          Icon(Icons.check_circle, color: NexoTones.income(context)),
          const SizedBox(width: 6),
          const Text('Bate com o banco',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ])
      else ...[
        Text(
            'Diferença: ${check.differenceCents > 0 ? '+' : '−'}${money(check.differenceCents.abs() / 100)}',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: NexoTones.warning(context))),
        const SizedBox(height: 6),
        FilledButton.tonalIcon(
            onPressed: () => onAdjust(linked, check),
            icon: const Icon(Icons.tune),
            label: const Text('Ajustar o Nexo (neutro)')),
      ],
    ]);
  }
}

/// One Nexo account that holds several bank accounts: their sum against it.
class _GroupCard extends StatelessWidget {
  const _GroupCard(
      {required this.account,
      required this.banks,
      required this.app,
      required this.money,
      required this.when,
      required this.onAdjust});
  final Account account;
  final List<BankAccountSnapshot> banks;
  final AppProvider app;
  final String Function(double) money;
  final DateFormat when;
  final void Function(Account, BalanceCheck) onAdjust;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall;
    final combined = combineBankAccounts(banks);
    final check = combined == null
        ? null
        : checkBalance(
            account: account,
            bank: combined,
            transactions: app.transactions,
            metadata: app.transactionMetadata);
    return NexoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance_wallet_outlined, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
              child: Text('${account.name} · soma de ${banks.length} contas',
                  style: const TextStyle(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        Text(banks.map((b) => b.bank).toSet().join(' + '), style: small),
        const SizedBox(height: 8),
        if (combined != null)
          Text('Nos bancos: ${money(combined.balanceCents! / 100)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFeatures: NexoTones.figures)),
        if (combined?.bankUpdatedAt != null)
          Text(
              'Conta a partir da leitura mais antiga: ${when.format(combined!.bankUpdatedAt!)}',
              style: small),
        _CheckView(
            linked: account, check: check, money: money, onAdjust: onAdjust),
      ]),
    );
  }
}
