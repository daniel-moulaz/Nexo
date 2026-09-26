import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/notification_inbox.dart';
import '../services/import_rules_service.dart';
import '../services/transaction_metadata_service.dart';
import '../utils/finance_input.dart';
import '../theme/app_theme.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});
  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> {
  List<Map<String, dynamic>>? rows;
  String? error;
  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    try {
      await NotificationInbox.sync();
      final result = await NotificationInbox.pending();
      if (mounted)
        setState(() {
          rows = result;
          error = null;
        });
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Não foi possível carregar as sugestões. Tente novamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    return Scaffold(
        appBar: AppBar(title: const Text('Sugestões de lançamentos'), actions: [
          IconButton(
              onPressed: reload,
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar')
        ]),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          const Text(
              'Nada é registrado sem sua confirmação. Revise conta, tipo e possíveis duplicatas. Sugestões expiram em 7 dias.'),
          if (error != null) Text(error!),
          if (rows == null && error == null) const LinearProgressIndicator(),
          if (rows?.isEmpty == true)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma sugestão para revisar.')),
          for (final row in rows ?? <Map<String, dynamic>>[])
            Card(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              app.settings.hideBalance
                                  ? '••••'
                                  : formatAmount(
                                      (row['amount_cents'] as int) / 100,
                                      'BRL'),
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(row['description']),
                          Text(
                              '${NotificationInbox.knownApps[row['app_id']] ?? row['app_id']} • ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(row['occurred_at']))}'),
                          Wrap(spacing: 8, children: [
                            FilledButton(
                                onPressed: () async {
                                  await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) =>
                                              SuggestionReviewScreen(
                                                  row: row)));
                                  await reload();
                                },
                                child: const Text('Registrar')),
                            TextButton(
                                onPressed: () async {
                                  try {
                                    await NotificationInbox.ignore(row['id']);
                                    await reload();
                                  } catch (_) {
                                    if (mounted)
                                      setState(() => error =
                                          'Não foi possível ignorar a sugestão. Tente novamente.');
                                  }
                                },
                                child: const Text('Ignorar'))
                          ]),
                        ]))),
        ]));
  }
}

class SuggestionReviewScreen extends StatefulWidget {
  final Map<String, dynamic> row;
  const SuggestionReviewScreen({super.key, required this.row});
  @override
  State<SuggestionReviewScreen> createState() => _SuggestionReviewScreenState();
}

class _SuggestionReviewScreenState extends State<SuggestionReviewScreen> {
  final amount = TextEditingController(),
      description = TextEditingController(),
      subcategory = TextEditingController();
  String type = 'expense';
  String? account, destination, category, error;
  bool busy = false;
  List<ImportRule> rules = [];
  @override
  void initState() {
    super.initState();
    type = widget.row['kind'] == 'refund' ? 'income' : widget.row['kind'];
    amount.text = ((widget.row['amount_cents'] as int) / 100)
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    description.text = widget.row['description'];
    loadRules();
  }

  Future<void> loadRules() async {
    rules = await ImportRulesService.load();
    if (!mounted) return;
    final rule = ImportRulesService.match(
        rules, description.text, type, context.read<AppProvider>().categories);
    setState(() {
      category = rule?.categoryId;
      subcategory.text = rule?.subcategory ?? '';
    });
  }

  @override
  void dispose() {
    amount.dispose();
    description.dispose();
    subcategory.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy) return;
    final app = context.read<AppProvider>();
    final value = parseMoney(amount.text);
    if (value == null ||
        value <= 0 ||
        description.text.trim().isEmpty ||
        account == null ||
        (type == 'transfer'
            ? destination == null || destination == account
            : category == null)) {
      setState(() => error =
          'Confira valor, descrição, conta e ${type == 'transfer' ? 'conta de destino' : 'categoria'}.');
      return;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(widget.row['occurred_at']);
    final candidates = ImportRulesService.candidates(app.transactions,
        accountId: account!,
        date: date,
        amount: value,
        type: type == 'transfer' ? 'expense' : type);
    if (candidates.isNotEmpty) {
      final proceed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Possível lançamento já registrado'),
                  content: const Text(
                      'Há um lançamento com a mesma conta, valor e data próxima. Volte e ignore a sugestão se for o mesmo movimento.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Voltar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Registrar separado'))
                  ]));
      if (proceed != true || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (type == 'transfer') {
        await app.addTransfer(
            fromId: account!,
            toId: destination!,
            fromAmount: value,
            occurredAt: date,
            note: description.text.trim(),
            suggestionId: widget.row['id']);
      } else {
        final id = 'notification:${widget.row['id']}';
        await app.addTransaction(
            AppTransaction(
                id: id,
                type: type,
                amount: value,
                description: description.text.trim(),
                accountId: account!,
                categoryId: category!,
                date: date,
                currency: 'BRL',
                note: widget.row['kind'] == 'refund'
                    ? 'Estorno / reembolso revisado'
                    : ''),
            metadata: TransactionMetadata(
                transactionId: id,
                source: 'notification',
                subcategory: subcategory.text.trim()),
            suggestionId: widget.row['id']);
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error =
              'Não foi possível registrar. A sugestão pode já ter sido resolvida. Atualize a caixa de entrada.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final accounts = app.accounts
        .where((a) =>
            !a.isGold &&
            a.currency == 'BRL' &&
            (type != 'transfer' || a.type != 'credit'))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Revisar sugestão')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(
              'Origem: ${NotificationInbox.knownApps[widget.row['app_id']] ?? widget.row['app_id']}'),
          Text(DateFormat('dd/MM/yyyy HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(widget.row['occurred_at']))),
          const Text(
              'Escolha a conta correta. Pix entre suas próprias contas é transferência, não receita ou despesa.'),
          DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('Despesa')),
                DropdownMenuItem(
                    value: 'income', child: Text('Receita / reembolso')),
                DropdownMenuItem(
                    value: 'transfer',
                    child: Text('Transferência entre minhas contas'))
              ],
              onChanged: busy
                  ? null
                  : (v) {
                      setState(() {
                        type = v!;
                        account = null;
                        destination = null;
                        category = null;
                      });
                      loadRules();
                    }),
          TextField(
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor em R\$')),
          TextField(
              controller: description,
              decoration: const InputDecoration(labelText: 'Descrição')),
          DropdownButtonFormField<String>(
              key: ValueKey('account$type'),
              initialValue: account,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Conta / cartão • selecione'),
              items: accounts
                  .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => account = v)),
          if (type == 'transfer')
            DropdownButtonFormField<String>(
                initialValue: destination,
                isExpanded: true,
                decoration:
                    const InputDecoration(labelText: 'Conta de destino'),
                items: accounts
                    .map((a) =>
                        DropdownMenuItem(value: a.id, child: Text(a.name)))
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => destination = v))
          else ...[
            DropdownButtonFormField<String>(
                key: ValueKey('$type$category'),
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: app.categories
                    .where((c) => c.type == type)
                    .map((c) =>
                        DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => category = v)),
            TextField(
                controller: subcategory,
                decoration: const InputDecoration(
                    labelText: 'Subcategoria (opcional)')),
          ],
          const SizedBox(height: 16),
          if (error != null) Text(error!),
          FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Salvando…' : 'Confirmar e registrar')),
        ]));
  }
}
