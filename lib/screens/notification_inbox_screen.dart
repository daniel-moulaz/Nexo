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
import '../services/pluggy_inbox.dart';
import '../services/inbox_reconciler.dart';
import '../services/reconciliation.dart';
import '../widgets/nexo_ui.dart';
import '../widgets/android_feature_notice.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});
  @override
  State<NotificationInboxScreen> createState() =>
      _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen>
    with WidgetsBindingObserver {
  InboxState? state;
  String? error;

  /// "Os dados de hoje ainda não chegaram…" (Open Finance is daily).
  String? _freshness;
  bool _showResolved = false;
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

  static bool get _available => PluggyInbox.instance != null;

  Future<void> reload({bool force = false}) async {
    if (!_available) return;
    try {
      String? syncError;
      String? freshness;
      if (PluggyInbox.instance case final pluggy?) {
        final problem = await pluggy.sync(force: force);
        if (problem != null) syncError = 'Open Finance: $problem';
        try {
          freshness = todayMissing(await pluggy.remote.items(), DateTime.now());
        } catch (_) {
          // Only a hint: the inbox works without it.
        }
      }
      if (!mounted) return;
      final app = context.read<AppProvider>();
      final result = await InboxReconciler.run(
          pendingRows: await NotificationInbox.pending(),
          transactions: app.transactions,
          metadata: app.transactionMetadata);
      if (mounted)
        setState(() {
          state = result;
          error = syncError;
          _freshness = freshness;
        });
    } catch (_) {
      if (mounted)
        setState(() =>
            error = 'Não foi possível carregar as sugestões. Tente novamente.');
    }
  }

  Future<void> _act(Future<void> Function() action, String done,
      {Future<void> Function()? undo}) async {
    try {
      await action();
      await reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(done),
          action: undo == null
              ? null
              : SnackBarAction(
                  label: 'Desfazer',
                  onPressed: () async {
                    try {
                      await undo();
                      await reload();
                    } catch (_) {
                      if (mounted)
                        setState(() => error =
                            'Não foi possível desfazer. Atualize e tente novamente.');
                    }
                  })));
    } catch (_) {
      if (mounted)
        setState(() => error =
            'Não foi possível concluir. A sugestão pode já ter sido resolvida.');
    }
  }

  Future<void> _undoIgnore(Iterable<String> ids) async {
    for (final id in ids) {
      await NotificationInbox.undoIgnore(id);
      if (PluggyInbox.isPluggy(id)) await PluggyInbox.instance?.undoIgnore(id);
    }
  }

  Future<void> _review(Map<String, dynamic> row,
      {String? type, String? categoryId}) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => SuggestionReviewScreen(
                row: row, initialType: type, suggestedCategory: categoryId)));
    await reload();
  }

  Future<void> _ownerName() async {
    final controller = TextEditingController(
        text: (await InboxReconciler.ownerNames()).join(', '));
    if (!mounted) return;
    final saved = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Seu nome no banco'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text(
                      'Como seu nome aparece em "Pix enviado/recebido". Serve para reconhecer dinheiro entre suas próprias contas. Fica só neste aparelho.'),
                  const SizedBox(height: 12),
                  TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(
                          hintText:
                              'Nome Sobrenome (separe variações por vírgula)')),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Salvar')),
                ]));
    if (saved == true) {
      await InboxReconciler.setOwnerNames(controller.text.split(','));
      await reload();
    }
  }

  Future<bool> _confirmMany(int count, String what) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
                  title: Text('Ignorar $count $what?'),
                  content: const Text(
                      'Nada é lançado nem apagado. Elas saem desta caixa e podem voltar com Desfazer.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('Ignorar')),
                  ])) ==
      true;

  @override
  Widget build(BuildContext context) {
    if (!_available)
      return const AndroidFeatureNotice(
          title: 'Sugestões',
          explanation:
              'A detecção bancária funciona no Android. Esta versão Windows é local e não recebe sugestões do celular.');
    final app = context.watch<AppProvider>();
    final hidden = app.settings.hideBalance;
    String money(int cents) =>
        hidden ? '••••' : formatAmount(cents / 100, 'BRL');
    String when(DateTime d) => DateFormat('dd/MM HH:mm').format(d);
    final matches = state?.matches ?? const <Match>[];
    final maybe =
        matches.where((m) => m.resolution == Resolution.maybe).toList();
    final own =
        matches.where((m) => m.resolution == Resolution.ownTransfer).toList();
    final fresh =
        matches.where((m) => m.resolution == Resolution.newEntry).toList();
    final resolved = state?.resolved ?? const <AutoResolved>[];
    final rows = {
      for (final m in matches)
        m.movement.id: {
          'id': m.movement.id,
          'app_id':
              m.movement.id.startsWith('pluggy:') ? 'pluggy' : 'notification',
          'amount_cents': m.movement.amountCents,
          'description': m.movement.description,
          'kind': m.movement.kind,
          'medium': 'unknown',
          'occurred_at': m.movement.occurredAt.millisecondsSinceEpoch,
        }
    };
    final cs = Theme.of(context).colorScheme;

    Widget movementCard(Match m,
        {List<Widget> extra = const [], Widget? hint}) {
      final mv = m.movement;
      final income = !mv.outgoing;
      return NexoCard(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(hidden ? 'Movimentação' : mv.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700))),
              Text('${income ? '+' : '−'}${money(mv.amountCents)}',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: income
                          ? NexoTones.income(context)
                          : NexoTones.expense(context))),
            ]),
            Text(
                '${NotificationInbox.knownApps[rows[mv.id]!['app_id']] ?? 'Banco'} · ${when(mv.occurredAt)}',
                style: Theme.of(context).textTheme.bodySmall),
            if (hint != null) ...[const SizedBox(height: 6), hint],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: extra),
          ]));
    }

    return Scaffold(
        appBar: AppBar(title: const Text('Para revisar'), actions: [
          PopupMenuButton<String>(
              tooltip: 'Opções',
              onSelected: (v) async {
                if (v == 'owner') await _ownerName();
                if (v == 'auto') {
                  await InboxReconciler.setAutomatic(
                      !await InboxReconciler.automatic());
                  await reload();
                }
                if (v == 'forget') {
                  await NotificationPreferences.clear();
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Contas sugeridas esquecidas.')));
                }
              },
              itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'owner', child: Text('Seu nome no banco')),
                    const PopupMenuItem(
                        value: 'auto',
                        child: Text('Ligar/desligar conciliação automática')),
                    const PopupMenuItem(
                        value: 'forget',
                        child: Text('Esquecer contas sugeridas')),
                  ]),
          IconButton(
              onPressed: () => reload(force: true),
              icon: const Icon(Icons.refresh),
              tooltip: 'Atualizar')
        ]),
        body: RefreshIndicator(
          onRefresh: () => reload(force: true),
          child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(error!, style: TextStyle(color: cs.error))),
                if (_freshness != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.schedule, size: 18, color: cs.tertiary),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_freshness!)),
                          ])),
                if (state == null && error == null)
                  const LinearProgressIndicator(),
                if (state != null) ...[
                  Text(
                      matches.isEmpty
                          ? 'Tudo em dia. Nada precisa de você agora.'
                          : '${matches.length} movimentação(ões) precisam de você. O app já resolveu o que era repetitivo.',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 12),
                ],
                if (resolved.isNotEmpty)
                  NexoCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        ListTile(
                            leading:
                                Icon(Icons.auto_awesome, color: cs.primary),
                            title: Text(
                                '${resolved.length} resolvida(s) automaticamente'),
                            subtitle: const Text(
                                'Já lançadas, estornos, reservas e rendimentos pequenos'),
                            trailing: Icon(_showResolved
                                ? Icons.expand_less
                                : Icons.expand_more),
                            onTap: () =>
                                setState(() => _showResolved = !_showResolved)),
                        if (_showResolved)
                          for (final r in resolved.take(60))
                            ListTile(
                                dense: true,
                                title: Text(
                                    hidden ? 'Movimentação' : r.description,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                    '${InboxReconciler.reasonLabel(r.reason)} · ${money(r.amountCents)}'),
                                trailing: r.undoable
                                    ? TextButton(
                                        onPressed: () => _act(
                                            () => InboxReconciler.undo(r),
                                            'Voltou para a revisão.'),
                                        child: const Text('Desfazer'))
                                    : null),
                      ])),
                if (maybe.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const NexoSectionTitle('Na dúvida',
                      subtitle: 'Parece um lançamento que você já fez',
                      icon: Icons.help_outline),
                  const SizedBox(height: 8),
                  for (final m in maybe)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: movementCard(m,
                            hint: Text(
                                'No Nexo: ${hidden ? 'lançamento' : m.transaction!.description} · ${hidden ? '••••' : formatAmount(m.transaction!.amount, 'BRL')} · ${DateFormat('dd/MM').format(m.transaction!.date)}',
                                style: TextStyle(color: cs.primary)),
                            extra: [
                              FilledButton.tonal(
                                  onPressed: () => _act(
                                      () => InboxReconciler.link(
                                          m.movement.id, m.transaction!.id),
                                      'Vinculado. Nada foi lançado de novo.'),
                                  child: const Text('É o mesmo')),
                              TextButton(
                                  onPressed: () => _act(
                                      () => InboxReconciler.dismissPair(
                                          m.movement.id, m.transaction!.id),
                                      'Separados.'),
                                  child: const Text('São diferentes')),
                            ])),
                ],
                if (own.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  NexoSectionTitle('Entre suas contas',
                      subtitle: 'Não é gasto nem receita',
                      icon: Icons.swap_horiz,
                      action: 'Ignorar todas', onAction: () async {
                    final ids = own.map((m) => m.movement.id).toList();
                    if (await _confirmMany(ids.length, 'movimentações')) {
                      await _act(() => InboxReconciler.ignoreAll(ids),
                          '${ids.length} ignoradas.',
                          undo: () => _undoIgnore(ids));
                    }
                  }),
                  const SizedBox(height: 8),
                  for (final m in own.where((m) => m.movement.outgoing))
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: movementCard(m,
                            hint: Text(
                                'Com: ${hidden ? 'entrada' : m.pair!.description} · ${when(m.pair!.occurredAt)}'),
                            extra: [
                              FilledButton.tonal(
                                  onPressed: () => _review(rows[m.movement.id]!,
                                      type: 'transfer'),
                                  child: const Text('Registrar transferência')),
                              TextButton(
                                  onPressed: () => _act(
                                      () => InboxReconciler.ignoreAll(
                                          [m.movement.id, m.pair!.id]),
                                      'Ignoradas.',
                                      undo: () => _undoIgnore(
                                          [m.movement.id, m.pair!.id])),
                                  child: const Text('Já está nos saldos')),
                            ])),
                  if (own.isNotEmpty)
                    TextButton.icon(
                        onPressed: _ownerName,
                        icon: const Icon(Icons.badge_outlined),
                        label: const Text(
                            'Informar seu nome para reconhecer melhor')),
                ],
                if (fresh.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  NexoSectionTitle('Novas',
                      subtitle: 'Sem lançamento parecido no Nexo',
                      icon: Icons.fiber_new_outlined,
                      action: 'Ignorar todas', onAction: () async {
                    final ids = fresh.map((m) => m.movement.id).toList();
                    if (await _confirmMany(ids.length, 'sugestões')) {
                      await _act(() => InboxReconciler.ignoreAll(ids),
                          '${ids.length} ignoradas.',
                          undo: () => _undoIgnore(ids));
                    }
                  }),
                  const SizedBox(height: 8),
                  for (final m in fresh)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: movementCard(m,
                            hint: m.categoryId == null
                                ? null
                                : Text(
                                    'Categoria sugerida: ${app.categoryById(m.categoryId!)?.name ?? '—'}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            extra: [
                              FilledButton(
                                  onPressed: () => _review(rows[m.movement.id]!,
                                      categoryId: m.categoryId),
                                  child: const Text('Revisar')),
                              TextButton(
                                  onPressed: () => _act(
                                      () => NotificationInbox.ignore(
                                          m.movement.id),
                                      'Sugestão ignorada.',
                                      undo: () => _undoIgnore([m.movement.id])),
                                  child: const Text('Ignorar')),
                            ])),
                ],
              ]),
        ));
  }
}

class SuggestionReviewScreen extends StatefulWidget {
  final Map<String, dynamic> row;

  /// Preselected type (e.g. transfer between own accounts).
  final String? initialType;

  /// Category learned from rules or past entries.
  final String? suggestedCategory;
  const SuggestionReviewScreen(
      {super.key, required this.row, this.initialType, this.suggestedCategory});
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
  bool alwaysCategory = false;

  /// What a rule should look for: the description without card prefixes
  /// and numbers ("Ifd*Wesley 123" → "wesley").
  String get rulePattern {
    var d = description.text.trim().toLowerCase();
    d = d.replaceFirst(
        RegExp(r'^(ifd\*|ifd |mp \*|mp\*|pg \*|pg\*|pag\*|pp\*)'), '');
    d = d.replaceAll(RegExp(r'[0-9]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
    d = d.trim();
    return d.length > 40 ? d.substring(0, 40).trim() : d;
  }

  late DateTime date;
  String get ruleScope => NotificationPreferences.scope(
      widget.row['app_id'], widget.row['medium'] ?? 'unknown', type);
  List<ImportRule> rules = [];
  @override
  void initState() {
    super.initState();
    type = widget.initialType ??
        (widget.row['kind'] == 'refund' ? 'income' : widget.row['kind']);
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
        category = rule?.categoryId ?? widget.suggestedCategory;
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
    setState(() {
      busy = true;
      error = null;
    });
    final candidates = ImportRulesService.candidates(app.transactions,
        accountId: account!,
        date: date,
        amount: value,
        type: type == 'transfer' ? 'expense' : type);
    if (candidates.isNotEmpty) {
      final proceed = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
                  title: const Text('Possível lançamento já registrado'),
                  content: Text(
                      'Há um lançamento com a mesma conta, valor e data próxima: "${candidates.first.description}". Se for o mesmo movimento, vincule; nada é lançado de novo.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(c, 'back'),
                        child: const Text('Voltar')),
                    TextButton(
                        onPressed: () => Navigator.pop(c, 'separate'),
                        child: const Text('Registrar separado')),
                    FilledButton(
                        onPressed: () => Navigator.pop(c, 'link'),
                        child: const Text('É o mesmo'))
                  ]));
      if (!mounted) return;
      if (proceed == 'link') {
        try {
          await InboxReconciler.link(
              widget.row['id'] as String, candidates.first.id);
          if (mounted) Navigator.pop(context);
        } catch (_) {
          if (mounted)
            setState(() {
              busy = false;
              error = 'Não foi possível vincular. Atualize a caixa.';
            });
        }
        return;
      }
      if (proceed != 'separate') {
        setState(() => busy = false);
        return;
      }
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
      if (alwaysCategory && type != 'transfer' && rulePattern.length >= 3) {
        try {
          await ImportRulesService.save(ImportRule(
              id: 'rule:$type:$rulePattern',
              pattern: rulePattern,
              type: type,
              categoryId: category!,
              subcategory: subcategory.text.trim()));
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
          if (type != 'transfer' && rulePattern.length >= 3)
            CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Sempre usar esta categoria para "$rulePattern"'),
                subtitle: const Text(
                    'Cria uma regra de importação. Você pode mudar em Regras.'),
                value: alwaysCategory,
                onChanged: busy
                    ? null
                    : (v) => setState(() => alwaysCategory = v ?? false)),
          const SizedBox(height: 16),
          if (error != null) Text(error!),
          FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Salvando…' : 'Confirmar e registrar')),
        ]));
  }
}
