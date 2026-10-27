import 'package:flutter/material.dart';
import '../widgets/nexo_ui.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/notification_service.dart';
import '../services/recurring_projection.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import 'recurring_detail_screen.dart';
import 'debt_overview_screen.dart';
import 'agenda_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/subscription_detector.dart';

class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});
  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String _expenseFilter = 'all', _view = 'active';
  Set<String> _dismissed = {};
  Future<List<RecurringHistoryEntry>>? _history;
  int? _historyCount;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    loadDismissedSubscriptions().then((v) {
      if (mounted) setState(() => _dismissed = v);
    });
  }

  Future<void> _dismiss(SubscriptionCandidate c) async {
    final next = {..._dismissed, c.key};
    setState(() => _dismissed = next);
    await (await SharedPreferences.getInstance())
        .setStringList(dismissedSubscriptionsKey, next.toList());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _open(RecurringPayment r) {
    final app = context.read<AppProvider>();
    Navigator.push(
        context,
        ExpensyRoute(
            builder: (_) => RecurringDetailScreen(
                recurring: r,
                fmt: (v) => formatAmount(
                    v,
                    app.accountById(r.accountId)?.currency ??
                        app.settings.currency))));
  }

  List<Widget> _subscriptions(AppProvider app, String Function(double) money) {
    final found = detectSubscriptions(app, _dismissed);
    if (found.isEmpty) return const [];
    final cs = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 8),
      Card(
        color: cs.tertiaryContainer.withValues(alpha: .35),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.auto_awesome_outlined, color: cs.tertiary),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Possíveis assinaturas',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 4),
            const Text(
                'Cobranças que se repetem todo mês com valor parecido e ainda não estão cadastradas. Cadastre para entrar na previsão e nos lembretes.'),
            for (final c in found.take(6))
              ListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '~${money(c.monthlyAmount)}/mês · vista em ${c.months} meses'),
                trailing: Wrap(spacing: 0, children: [
                  IconButton(
                      tooltip: 'Não é assinatura',
                      onPressed: () => _dismiss(c),
                      icon: const Icon(Icons.close)),
                  FilledButton.tonal(
                      onPressed: () =>
                          openRecurringSheet(context, suggestion: c),
                      child: const Text('Cadastrar')),
                ]),
              ),
          ]),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final today = RecurringProjection.day(DateTime.now());
    final until = DateTime(today.year, today.month + 3, 0);
    final type = _tabs.index == 0 ? 'expense' : 'income';
    final filtered = app.recurring
        .where((r) =>
            r.paymentType == type &&
            (_tabs.index == 1 ||
                _expenseFilter == 'all' ||
                r.recurringType == _expenseFilter))
        .toList()
      ..sort((a, b) => a.nextActionDate.compareTo(b.nextActionDate));
    final active = filtered.where((r) => r.canComplete).toList();
    final shown = _view == 'ended'
        ? filtered.where((r) => !r.canComplete).toList()
        : active;
    final projection = RecurringProjection.calculate(active,
        until: until, registeredIds: app.transactions.map((t) => t.id).toSet());
    double sum(Iterable<RecurringOccurrence> rows) => rows.fold(
        0,
        (s, e) =>
            s +
            app.convertToMain(
                e.amount,
                app.accountById(e.recurring.accountId)?.currency ??
                    app.settings.currency));
    String money(double amount) => app.settings.hideBalance
        ? '••••'
        : formatAmount(amount, app.settings.currency);
    final overdue = projection.occurrences.where((e) => e.date.isBefore(today));
    final thisMonth = projection.occurrences.where((e) =>
        !e.date.isBefore(today) &&
        e.date.isBefore(DateTime(today.year, today.month + 1)));
    final future =
        projection.occurrences.where((e) => !e.date.isBefore(today)).toList();
    if (_view == 'history' &&
        (_history == null || _historyCount != app.recurringHistoryCount)) {
      _historyCount = app.recurringHistoryCount;
      _history = DBHelper.getAllRecurringHistory();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorrentes'),
        automaticallyImplyLeading: Navigator.canPop(context),
        actions: [
          IconButton(
              tooltip: 'Adicionar recorrente',
              icon: const Icon(Icons.add),
              onPressed: () => openRecurringSheet(context, defaultType: type)),
        ],
        bottom: TabBar(controller: _tabs, tabs: const [
          Tab(text: 'Despesas'),
          Tab(text: 'Receitas'),
        ]),
      ),
      body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            NexoChipRow(children: [
              for (final e in const {
                'active': 'Em aberto',
                'future': 'Próximos meses',
                'history': 'Histórico',
                'ended': 'Encerradas'
              }.entries)
                ChoiceChip(
                    label: Text(e.value),
                    selected: _view == e.key,
                    onSelected: (_) => setState(() => _view = e.key)),
            ]),
            if (_tabs.index == 0)
              Align(
                alignment: Alignment.centerLeft,
                child: PopupMenuButton<String>(
                  tooltip: 'Filtrar tipo de recorrência',
                  initialValue: _expenseFilter,
                  onSelected: (value) => setState(() => _expenseFilter = value),
                  itemBuilder: (_) => [
                    for (final e in const {
                      'all': 'Todos os tipos',
                      'subscription': 'Fixas / assinaturas',
                      'installment': 'Parceladas',
                    }.entries)
                      CheckedPopupMenuItem(
                        value: e.key,
                        checked: _expenseFilter == e.key,
                        child: Text(e.value),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.filter_list, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                          child: Text(const {
                        'all': 'Todos os tipos',
                        'subscription': 'Fixas / assinaturas',
                        'installment': 'Parceladas',
                      }[_expenseFilter]!)),
                      const Icon(Icons.arrow_drop_down),
                    ]),
                  ),
                ),
              ),
            if (_tabs.index == 0 && _view == 'active')
              ..._subscriptions(app, money),
            if (_view == 'active' || _view == 'future') ...[
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(type == 'expense'
                                ? 'A pagar até o fim do mês'
                                : 'A receber até o fim do mês'),
                            Text(money(sum(thisMonth)),
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                            Text(
                                '${thisMonth.length} ${thisMonth.length == 1 ? 'vencimento' : 'vencimentos'} de hoje até ${ptDate(DateTime(today.year, today.month + 1, 0))}'),
                            if (overdue.isNotEmpty)
                              Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                      'Em atraso: ${money(sum(overdue))} • ${overdue.length} vencimentos',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error))),
                            const SizedBox(height: 8),
                            const Text(
                                'Somente recorrentes cadastradas. Valores no cartão entram na fatura; não são débito imediato em conta.',
                                style: TextStyle(fontSize: 12)),
                            if (projection.incomplete)
                              const Text(
                                  'Projeção parcial: revise frequências inválidas ou muito antigas.'),
                          ]))),
            ],
            if (_view == 'active') ...[
              NexoChipRow(children: [
                TextButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        ExpensyRoute(
                            builder: (_) => const DebtOverviewScreen())),
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text('Dívidas e compromissos')),
                TextButton.icon(
                    onPressed: () => Navigator.push(context,
                        ExpensyRoute(builder: (_) => const AgendaScreen())),
                    icon: const Icon(Icons.event_note),
                    label: const Text('Ver saldo previsto')),
              ]),
              if (shown.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Nenhuma recorrência em aberto neste filtro. Use + para cadastrar uma conta fixa ou receita.')),
              for (final r in shown) _RecurringTile(recurring: r),
            ],
            if (_view == 'ended') ...[
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      'Cronogramas concluídos. O histórico continua disponível.')),
              if (shown.isEmpty)
                const Text('Nenhuma recorrência encerrada neste filtro.'),
              for (final r in shown) _RecurringTile(recurring: r),
            ],
            if (_view == 'future') ...[
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      'Previsão pelo calendário • não registra pagamentos')),
              for (var offset = 0; offset < 3; offset++)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        '${(today.month + offset - 1) % 12 + 1}/${DateTime(today.year, today.month + offset).year}'),
                    trailing: Text(money(sum(future.where((e) =>
                        e.date.year ==
                            DateTime(today.year, today.month + offset).year &&
                        e.date.month ==
                            DateTime(today.year, today.month + offset)
                                .month))))),
              for (final e in future.take(80))
                Card(
                    child: ListTile(
                        title: Text(e.recurring.name),
                        subtitle: Text(
                            '${ptDate(e.date)} • ${app.accountById(e.recurring.accountId)?.name ?? 'Conta removida'}'),
                        trailing: Text(app.settings.hideBalance
                            ? '••••'
                            : formatAmount(
                                e.amount,
                                app
                                        .accountById(e.recurring.accountId)
                                        ?.currency ??
                                    app.settings.currency)),
                        onTap: () => _open(e.recurring))),
              if (future.isEmpty)
                const Text('Nenhum vencimento previsto nestes três meses.'),
              if (future.length > 80)
                const Text(
                    'Exibindo os primeiros 80 vencimentos. Os totais incluem todo o período.'),
            ],
            if (_view == 'history')
              FutureBuilder<List<RecurringHistoryEntry>>(
                  future: _history,
                  builder: (context, snapshot) {
                    if (snapshot.hasError)
                      return TextButton(
                          onPressed: () => setState(() {
                                _history = DBHelper.getAllRecurringHistory();
                              }),
                          child: const Text(
                              'Não foi possível carregar. Tentar novamente'));
                    if (!snapshot.hasData)
                      return const Center(child: CircularProgressIndicator());
                    final ids = filtered.map((r) => r.id).toSet();
                    final rows = snapshot.data!
                        .where((h) => ids.contains(h.recurringId))
                        .toList();
                    final paid = rows.where((h) => h.action == 'paid');
                    final total = paid.fold<double>(0,
                        (s, h) => s + app.convertToMain(h.amount, h.currency));
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                  'Registrado como ${type == 'income' ? 'recebido' : 'pago'}: ${money(total)} • ${paid.length} ocorrências')),
                          const Text(
                              'Datas de vencimento das ocorrências. Pular não é pagar.'),
                          if (rows.isEmpty)
                            const Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                    'Ainda não há histórico neste filtro.')),
                          for (final h in rows.take(100))
                            Card(
                                child: ListTile(
                                    title: Text(filtered
                                        .firstWhere(
                                            (r) => r.id == h.recurringId)
                                        .name),
                                    subtitle: Text(
                                        '${ptDate(h.date)} • ${h.action == 'paid' ? (type == 'income' ? 'Recebida' : 'Paga') : 'Pulada / não paga'}'),
                                    trailing: Text(app.settings.hideBalance
                                        ? '••••'
                                        : formatAmount(h.amount, h.currency)),
                                    onTap: () => _open(filtered.firstWhere(
                                        (r) => r.id == h.recurringId)))),
                          if (rows.length > 100)
                            const Text(
                                'Mostrando as 100 ocorrências mais recentes. Total de todo o histórico deste filtro.'),
                        ]);
                  }),
          ]),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  final RecurringPayment recurring;

  const _RecurringTile({required this.recurring});

  String _frequency() {
    final n = recurring.freqVal <= 0 ? 1 : recurring.freqVal;
    if (n == 1) {
      switch (recurring.freqUnit) {
        case 'days':
          return 'Diária';
        case 'weeks':
          return 'Semanal';
        case 'years':
          return 'Anual';
        default:
          return 'Mensal';
      }
    }
    final unit = switch (recurring.freqUnit) {
      'days' => 'dias',
      'weeks' => 'semanas',
      'years' => 'anos',
      _ => 'meses',
    };
    return 'A cada $n $unit';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppProvider>();
    final cs = Theme.of(context).colorScheme;
    final account = app.accountById(recurring.accountId);
    final category = app.categoryById(recurring.categoryId);
    final currency = account?.currency ?? app.settings.currency;
    final today = DateTime.now();
    final now = DateTime(today.year, today.month, today.day);
    final due = DateTime(
      recurring.nextActionDate.year,
      recurring.nextActionDate.month,
      recurring.nextActionDate.day,
    );
    final days = due.difference(now).inDays;
    final overdue = days < 0;
    final total = recurring.totalPayments;
    final progress = total != null && total > 0 ? recurring.progress : null;

    final dueLabel = !recurring.canComplete
        ? 'Encerrada'
        : overdue
            ? 'Atrasada há ${days.abs()} dia${days.abs() == 1 ? '' : 's'}'
            : days == 0
                ? 'Vence hoje'
                : 'Vence em $days dia${days == 1 ? '' : 's'}';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          ExpensyRoute(
            builder: (_) => RecurringDetailScreen(
              recurring: recurring,
              fmt: (value) => formatAmount(value, currency),
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: category == null
                        ? cs.primaryContainer
                        : Color(category.colorValue).withValues(alpha: .16),
                    child: Icon(
                      recurring.paymentType == 'income'
                          ? Icons.south_west_rounded
                          : recurring.recurringType == 'installment'
                              ? Icons.payments_outlined
                              : Icons.autorenew_rounded,
                      color: category == null
                          ? cs.primary
                          : Color(category.colorValue),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          recurring.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (account != null) account.name,
                            if (category != null) category.name,
                            _frequency(),
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Capped so large text never pushes the amount off the
                  // card: the amount scales down, the status wraps.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            app.settings.hideBalance
                                ? '••••'
                                : formatAmount(
                                    recurring.nextActionAmount, currency),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                        Text(
                          dueLabel,
                          maxLines: 2,
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: overdue ? cs.error : cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (progress != null) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: progress, minHeight: 5),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${recurring.progressPayments}/$total ${recurring.canSkip ? 'concluídas' : 'pagas'} • ${recurring.remainingPayments} restantes',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                children: [
                  if (recurring.canSkip)
                    TextButton.icon(
                      onPressed: !recurring.canComplete
                          ? null
                          : () async {
                              await confirmRecurringAction(
                                  context, app, recurring,
                                  skip: true);
                            },
                      icon: const Icon(Icons.skip_next_rounded, size: 18),
                      label: const Text('Pular'),
                    ),
                  const SizedBox(width: 4),
                  FilledButton.tonalIcon(
                    onPressed: !recurring.canComplete
                        ? null
                        : () async {
                            await confirmRecurringAction(
                                context, app, recurring);
                          },
                    icon: Icon(
                      recurring.paymentType == 'income'
                          ? Icons.check_rounded
                          : Icons.done_all_rounded,
                      size: 18,
                    ),
                    label: Text(
                      recurring.paymentType == 'income'
                          ? 'Registrar recebimento'
                          : 'Registrar pagamento',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> confirmRecurringAction(
    BuildContext context, AppProvider app, RecurringPayment recurring,
    {bool skip = false}) async {
  final account = app.accountById(recurring.accountId);
  final value = app.settings.hideBalance
      ? 'valor oculto'
      : formatAmount(recurring.nextActionAmount,
          account?.currency ?? app.settings.currency);
  final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
              title:
                  Text(skip ? 'Pular esta ocorrência?' : 'Confirmar registro?'),
              content: Text(skip
                  ? '${recurring.name} • ${ptDate(recurring.nextActionDate)}\nNão registra pagamento nem altera saldo. A próxima ocorrência seguirá o calendário.'
                  : '${recurring.name} • $value\nVencimento: ${ptDate(recurring.nextActionDate)}\nConta: ${account?.name ?? 'Conta removida'}\n${account?.type == 'credit' ? 'Será registrado no cartão; a conta bancária só muda ao pagar a fatura.' : 'Este registro altera o saldo da conta.'}'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(skip ? 'Pular ocorrência' : 'Confirmar'))
              ]));
  if (accepted != true || !context.mounted) return;
  try {
    if (skip) {
      await app.skipNextRecurring(recurring);
    } else {
      await app.markRecurringPaid(recurring);
    }
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(skip
              ? 'Ocorrência pulada, sem pagamento.'
              : 'Registro concluído. Histórico atualizado.')));
  } catch (_) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Não foi possível concluir. Confira o histórico antes de tentar novamente.')));
  }
}

const dismissedSubscriptionsKey = 'nexo_subscription_dismissed_v1';

Future<Set<String>> loadDismissedSubscriptions() async =>
    ((await SharedPreferences.getInstance())
                .getStringList(dismissedSubscriptionsKey) ??
            const <String>[])
        .toSet();

List<SubscriptionCandidate> detectSubscriptions(
        AppProvider app, Set<String> dismissed) =>
    SubscriptionDetector.detect(
        transactions: app.transactions,
        metadata: app.transactionMetadata,
        recurring: app.recurring,
        now: DateTime.now(),
        amount: (t) => app.convertToMain(
            t.amount,
            t.currency.isEmpty
                ? app.accountById(t.accountId)?.currency ??
                    app.settings.currency
                : t.currency),
        dismissed: dismissed);

void openRecurringSheet(
  BuildContext context, {
  RecurringPayment? existing,
  String defaultType = 'expense',
  SubscriptionCandidate? suggestion,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _RecurringEditor(
      existing: existing,
      defaultType: defaultType,
      suggestion: suggestion,
    ),
  );
}

class _RecurringEditor extends StatefulWidget {
  final RecurringPayment? existing;
  final String defaultType;

  /// Prefill from a detected subscription; the person still reviews and saves.
  final SubscriptionCandidate? suggestion;

  const _RecurringEditor({
    this.existing,
    required this.defaultType,
    this.suggestion,
  });

  @override
  State<_RecurringEditor> createState() => _RecurringEditorState();
}

class _RecurringEditorState extends State<_RecurringEditor> {
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _frequencyCtrl = TextEditingController(text: '1');
  final _installmentsCtrl = TextEditingController(text: '12');
  final _notesCtrl = TextEditingController();

  late String _type;
  String _recurringType = 'subscription';
  String _frequencyUnit = 'months';
  DateTime _firstDate = DateTime.now();
  String? _accountId;
  String? _categoryId;
  bool _reminder = false;
  bool _earlyReminder = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);
  bool _submitted = false;
  bool _saving = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _type = widget.defaultType;
    final app = context.read<AppProvider>();
    final accounts = app.accounts.where((a) => !a.isGold).toList();
    if (accounts.isNotEmpty) _accountId = accounts.first.id;
    final categories = app.categories.where((c) => c.type == _type).toList();
    if (categories.isNotEmpty) _categoryId = categories.first.id;

    final sug = widget.suggestion;
    if (widget.existing == null && sug != null) {
      _type = 'expense';
      _recurringType = 'subscription';
      _nameCtrl.text = sug.label;
      _amountCtrl.text =
          sug.monthlyAmount.toStringAsFixed(2).replaceAll('.', ',');
      if (app.accountById(sug.accountId) != null) _accountId = sug.accountId;
      if (app.categories.any((c) => c.id == sug.categoryId)) {
        _categoryId = sug.categoryId;
      }
      // Next charge one month after the last one seen.
      final l = sug.lastDate;
      _firstDate = DateTime(l.year, l.month + 1,
          l.day.clamp(1, DateTime(l.year, l.month + 2, 0).day));
    }
    final e = widget.existing;
    if (e != null) {
      _type = e.paymentType;
      _recurringType = e.recurringType;
      _nameCtrl.text = e.name;
      _amountCtrl.text = e.amount.toStringAsFixed(2).replaceAll('.', ',');
      _frequencyCtrl.text = '${e.freqVal}';
      _frequencyUnit = e.freqUnit;
      _firstDate = e.startDate;
      _accountId = e.accountId;
      _categoryId = e.categoryId;
      _reminder = e.reminderEnabled;
      _earlyReminder = e.earlyReminderEnabled;
      _notesCtrl.text = e.notes;
      final parts = e.reminderTime.split(':');
      _reminderTime = TimeOfDay(
        hour: int.tryParse(parts.firstOrNull ?? '') ?? 9,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      );
      if (e.recurringType == 'installment') {
        _installmentsCtrl.text = '${e.totalPayments ?? 1}';
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _frequencyCtrl.dispose();
    _installmentsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _setType(String type) {
    final app = context.read<AppProvider>();
    final categories = app.categories.where((c) => c.type == type).toList();
    setState(() {
      _type = type;
      _categoryId = categories.firstOrNull?.id;
      if (type == 'income') _recurringType = 'subscription';
    });
  }

  DateTime _addPeriods(DateTime start, int count) {
    if (count <= 0) return start;
    final freq = int.tryParse(_frequencyCtrl.text) ?? 1;
    final steps = count * (freq <= 0 ? 1 : freq);
    switch (_frequencyUnit) {
      case 'days':
        return start.add(Duration(days: steps));
      case 'weeks':
        return start.add(Duration(days: steps * 7));
      case 'years':
        return DateTime(start.year + steps, start.month, start.day);
      default:
        final targetMonth = start.month + steps;
        final year = start.year + (targetMonth - 1) ~/ 12;
        final month = ((targetMonth - 1) % 12) + 1;
        final maxDay = DateTime(year, month + 1, 0).day;
        return DateTime(year, month, start.day.clamp(1, maxDay));
    }
  }

  Future<void> _toggleReminder(bool enabled) async {
    if (!enabled) {
      setState(() => _reminder = false);
      return;
    }
    final service = NotificationService();
    final allowed =
        await service.hasPermission() || await service.requestPermissions();
    if (!mounted) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Permita notificações para ativar lembretes.')),
      );
      return;
    }
    setState(() => _reminder = true);
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    final amount = parseMoney(_amountCtrl.text);
    final frequency = int.tryParse(_frequencyCtrl.text.trim());
    final installments = int.tryParse(_installmentsCtrl.text.trim());

    final validInstallments = _type != 'expense' ||
        _recurringType != 'installment' ||
        (installments != null && installments > 0);
    if (_nameCtrl.text.trim().isEmpty ||
        amount == null ||
        amount <= 0 ||
        frequency == null ||
        frequency <= 0 ||
        _accountId == null ||
        _categoryId == null ||
        !validInstallments) {
      final errors = <String>[
        if (_nameCtrl.text.trim().isEmpty) 'descrição',
        if (amount == null || amount <= 0) 'valor',
        if (frequency == null || frequency <= 0) 'frequência',
        if (_accountId == null) 'conta',
        if (_categoryId == null) 'categoria',
        if (!validInstallments) 'quantidade de parcelas',
      ];
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Revise: ${errors.join(', ')}.')));
      return;
    }

    setState(() => _saving = true);
    final app = context.read<AppProvider>();
    final existing = widget.existing;
    final count = _recurringType == 'installment' ? installments! : null;
    final endDate = count == null ? null : _addPeriods(_firstDate, count - 1);
    final reminderText =
        '${_reminderTime.hour.toString().padLeft(2, '0')}:${_reminderTime.minute.toString().padLeft(2, '0')}';

    final recurring = RecurringPayment(
      id: existing?.id ?? app.newId(),
      name: _nameCtrl.text.trim(),
      accountId: _accountId!,
      categoryId: _categoryId!,
      amount: amount,
      paymentType: _type,
      recurringType: _type == 'expense' ? _recurringType : 'subscription',
      freqVal: frequency,
      freqUnit: _frequencyUnit,
      startDate: _firstDate,
      nextDate: existing == null || existing.completedOccurrences == 0
          ? _firstDate
          : existing.nextDate,
      endDate: endDate,
      paidPayments: existing?.paidPayments ?? 0,
      skippedOccurrences: existing?.skippedOccurrences ?? const [],
      reminderEnabled: _reminder,
      reminderTime: reminderText,
      earlyReminderEnabled: _reminder && _earlyReminder,
      notes: _notesCtrl.text.trim(),
    );

    try {
      if (existing == null) {
        await app.addRecurring(recurring);
      } else {
        await app.updateRecurring(recurring);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Não foi possível salvar o recorrente. Tente novamente.')));
      }
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accounts = app.accounts.where((a) => !a.isGold).toList();
    final categories = app.categories.where((c) => c.type == _type).toList();
    final amount = parseMoney(_amountCtrl.text);
    final frequency = int.tryParse(_frequencyCtrl.text.trim());
    final installments = int.tryParse(_installmentsCtrl.text.trim());

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: .9,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEdit ? 'Editar recorrente' : 'Novo recorrente',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expense',
                        label: Text('Despesa'),
                        icon: Icon(Icons.north_east_rounded),
                      ),
                      ButtonSegment(
                        value: 'income',
                        label: Text('Receita'),
                        icon: Icon(Icons.south_west_rounded),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (value) => _setType(value.first),
                  ),
                  if (_type == 'expense') ...[
                    const SizedBox(height: 12),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'subscription',
                          label: Text('Fixa/assinatura'),
                          icon: Icon(Icons.autorenew_rounded),
                        ),
                        ButtonSegment(
                          value: 'installment',
                          label: Text('Parcelada'),
                          icon: Icon(Icons.payments_outlined),
                        ),
                      ],
                      selected: {_recurringType},
                      onSelectionChanged: (value) {
                        setState(() => _recurringType = value.first);
                      },
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Descrição',
                      hintText: 'Ex.: Internet, salário, Netflix...',
                      prefixIcon: const Icon(Icons.edit_note_rounded),
                      errorText: _submitted && _nameCtrl.text.trim().isEmpty
                          ? 'Informe uma descrição.'
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor por ocorrência',
                      prefixText:
                          '${currencyInfo(app.settings.currency).symbol} ',
                      errorText: _submitted && (amount == null || amount <= 0)
                          ? 'Informe um valor válido.'
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: TextField(
                          controller: _frequencyCtrl,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'A cada',
                            errorText: _submitted &&
                                    (frequency == null || frequency <= 0)
                                ? 'Inválido'
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: _frequencyUnit,
                          decoration:
                              const InputDecoration(labelText: 'Período'),
                          items: const [
                            DropdownMenuItem(
                                value: 'days', child: Text('dia(s)')),
                            DropdownMenuItem(
                                value: 'weeks', child: Text('semana(s)')),
                            DropdownMenuItem(
                                value: 'months', child: Text('mês(es)')),
                            DropdownMenuItem(
                                value: 'years', child: Text('ano(s)')),
                          ],
                          onChanged: (value) {
                            if (value != null)
                              setState(() => _frequencyUnit = value);
                          },
                        ),
                      ),
                    ],
                  ),
                  if (_type == 'expense' &&
                      _recurringType == 'installment') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _installmentsCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Quantidade de parcelas',
                        hintText: 'Ex.: 12',
                        prefixIcon:
                            const Icon(Icons.format_list_numbered_rounded),
                        errorText: _submitted &&
                                (installments == null || installments <= 0)
                            ? 'Informe a quantidade de parcelas.'
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: const Icon(Icons.calendar_today_outlined),
                    title: const Text('Primeira ocorrência'),
                    subtitle: Text(ptDate(_firstDate)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _firstDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2140),
                        cancelText: 'Cancelar',
                        confirmText: 'Selecionar',
                      );
                      if (picked != null) setState(() => _firstDate = picked);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Conta',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  if (accounts.isEmpty)
                    const _MissingDataCard(
                      icon: Icons.account_balance_wallet_outlined,
                      text: 'Cadastre uma conta antes de criar um recorrente.',
                    )
                  else
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: accounts.any((a) => a.id == _accountId)
                          ? _accountId
                          : null,
                      decoration: InputDecoration(
                        labelText: _type == 'income'
                            ? 'Onde o dinheiro entra'
                            : 'De onde sai o dinheiro',
                        errorText: _submitted && _accountId == null
                            ? 'Escolha uma conta.'
                            : null,
                      ),
                      items: accounts
                          .map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _accountId = value),
                    ),
                  const SizedBox(height: 14),
                  Text(
                    'Categoria',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 6),
                  if (categories.isEmpty)
                    _MissingDataCard(
                      icon: Icons.category_outlined,
                      text: _type == 'income'
                          ? 'Cadastre uma categoria de receita.'
                          : 'Cadastre uma categoria de despesa.',
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: categories.map((category) {
                        return ChoiceChip(
                          selected: _categoryId == category.id,
                          label: Text(category.name),
                          avatar: CircleAvatar(
                            radius: 4,
                            backgroundColor: Color(category.colorValue),
                          ),
                          onSelected: (_) =>
                              setState(() => _categoryId = category.id),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lembrete no vencimento'),
                    subtitle: Text(
                      _reminder
                          ? 'Avisar às ${_reminderTime.format(context)}'
                          : 'Receba uma notificação quando chegar a data.',
                    ),
                    value: _reminder,
                    onChanged: _toggleReminder,
                  ),
                  if (_reminder) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.access_time_rounded),
                      title: const Text('Horário do lembrete'),
                      trailing: Text(
                        _reminderTime.format(context),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _reminderTime,
                        );
                        if (picked != null)
                          setState(() => _reminderTime = picked);
                      },
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Avisar também 2 dias antes'),
                      value: _earlyReminder,
                      onChanged: (value) =>
                          setState(() => _earlyReminder = value),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: _notesCtrl,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Observação (opcional)',
                      prefixIcon: Icon(Icons.sticky_note_2_outlined),
                    ),
                  ),
                  if (_type == 'expense' &&
                      _recurringType == 'installment' &&
                      installments != null &&
                      installments > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$installments parcelas • termina em ${ptDate(_addPeriods(_firstDate, installments - 1))}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(isEdit ? Icons.save_outlined : Icons.check_rounded),
                label: Text(isEdit ? 'Salvar alterações' : 'Salvar recorrente'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MissingDataCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _MissingDataCard({required this.icon, required this.text});

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
