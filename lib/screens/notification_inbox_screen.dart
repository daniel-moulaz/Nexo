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
import '../services/notification_preferences.dart';
import 'automation_settings_screen.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});
  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>>? rows;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reload();
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
              tooltip: 'Configurar detecção',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AutomationSettingsScreen()))),
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
                          Text(app.settings.hideBalance
                              ? 'Movimentação detectada'
                              : row['description']),
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
                                child: const Text('Revisar')),
                            TextButton(
                                onPressed: () async {
                                  try {
                                    await NotificationInbox.ignore(row['id']);
                                    await reload();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: const Text(
                                                  'Sugestão ignorada.'),
                                              action: SnackBarAction(
                                                  label: 'Desfazer',
                                                  onPressed: () async {
                                                    try {
                                                      await NotificationInbox
                                                          .undoIgnore(
                                                              row['id']);
                                                      await reload();
                                                    } catch (_) {
                                                      if (mounted)
                                                        setState(() => error =
                                                            'Não foi possível desfazer. Atualize e tente novamente.');
                                                    }
                                                  })));
                                    }
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
  bool remember = false;
  late DateTime date;
  String get ruleScope => NotificationPreferences.scope(
      widget.row['app_id'], widget.row['medium'] ?? 'unknown', type);
  List<ImportRule> rules = [];
  @override
  void initState() {
    super.initState();
    type = widget.row['kind'] == 'refund' ? 'income' : widget.row['kind'];
    date = DateTime.fromMillisecondsSinceEpoch(widget.row['occurred_at']);
    amount.text = ((widget.row['amount_cents'] as int) / 100)
        .toStringAsFixed(2)
        .replaceAll('.', ',');
    description.text = widget.row['description'];
    loadRules();
  }

  Future<void> loadRules() async {
    setState(() => busy = true);
    try {
      rules = await ImportRulesService.load();
      final accounts = await NotificationPreferences.load();
      if (!mounted) return;
      final rule = ImportRulesService.match(rules, description.text, type,
          context.read<AppProvider>().categories);
      setState(() {
        category = rule?.categoryId;
        subcategory.text = rule?.subcategory ?? '';
        account = NotificationPreferences.suggest(
            accounts, ruleScope, context.read<AppProvider>().accounts,
            medium: widget.row['medium'] ?? 'unknown', type: type);
        busy = false;
      });
    } catch (_) {
      if (mounted)
        setState(() {
          busy = false;
          error =
              'Não foi possível carregar as regras. Você pode revisar os campos manualmente.';
        });
    }
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
                source: widget.row['kind'] == 'refund' && type == 'income'
                    ? 'notification_refund'
                    : 'notification',
                subcategory: subcategory.text.trim()),
            suggestionId: widget.row['id']);
      }
      // Preferences must never turn a successful financial save into a retry.
      var remembered = true;
      if (remember) {
        try {
          await NotificationPreferences.remember(ruleScope, account!);
        } catch (_) {
          remembered = false;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(remembered
                ? 'Lançamento registrado.'
                : 'Lançamento registrado; não foi possível lembrar a conta.')));
        Navigator.pop(context);
      }
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
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data da movimentação'),
              subtitle: Text(DateFormat('dd/MM/yyyy HH:mm').format(date)),
              trailing: const Icon(Icons.calendar_month),
              onTap: busy
                  ? null
                  : () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now());
                      if (picked != null && mounted)
                        setState(() => date = DateTime(picked.year,
                            picked.month, picked.day, date.hour, date.minute));
                    }),
          const Text(
              'Escolha a conta correta. Pix entre suas próprias contas é transferência, não receita ou despesa.'),
          DropdownButtonFormField<String>(
              initialValue: type,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('Despesa')),
                DropdownMenuItem(
                    value: 'income', child: Text('Receita / reembolso')),
                DropdownMenuItem(
                    value: 'transfer',
                    child: Text('Transferência entre minhas contas',
                        overflow: TextOverflow.ellipsis))
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
              enabled: !busy,
              controller: amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Valor em R\$')),
          TextField(
              enabled: !busy,
              controller: description,
              decoration: const InputDecoration(labelText: 'Descrição')),
          DropdownButtonFormField<String>(
              key: ValueKey('account$type$account'),
              initialValue: account,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Conta / cartão • confira antes de salvar'),
              items: accounts
                  .map(
                      (a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                  .toList(),
              onChanged: busy ? null : (v) => setState(() => account = v)),
          CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Lembrar esta escolha'),
              subtitle: const Text(
                  'Sugerir esta conta para o mesmo app, meio e tipo. Você sempre confirma.'),
              value: remember,
              onChanged:
                  busy ? null : (v) => setState(() => remember = v ?? false)),
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
