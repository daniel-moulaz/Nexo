import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';
import '../services/transaction_filter.dart';
import '../utils/finance_input.dart';
import '../widgets/desktop_transaction_table.dart';
import '../services/finance_rules.dart';
import '../widgets/nexo_ui.dart';
import '../widgets/shared_widgets.dart' show CategoryDot;

class TransactionSearchScreen extends StatefulWidget {
  final FocusNode? searchFocus;
  final bool autofocus;
  const TransactionSearchScreen(
      {super.key, this.searchFocus, this.autofocus = true});

  @override
  State<TransactionSearchScreen> createState() =>
      _TransactionSearchScreenState();
}

class _TransactionSearchScreenState extends State<TransactionSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  String _type = 'all';
  TransactionFilter _filter = TransactionFilter();

  Future<void> _filters() async {
    final previous = _filter.copy();
    var applied = false;
    final app = context.read<AppProvider>();
    final min = TextEditingController(
        text: _filter.minimum?.toString().replaceAll('.', ',') ?? '');
    final max = TextEditingController(
        text: _filter.maximum?.toString().replaceAll('.', ',') ?? '');
    String? error;
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, update) {
              Widget choice(
                      String label,
                      String? value,
                      Map<String, String> options,
                      void Function(String?) change) =>
                  DropdownButtonFormField<String>(
                      key: ValueKey('$label:$value'),
                      initialValue: options.containsKey(value) ? value : null,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: label),
                      items: [
                        const DropdownMenuItem<String>(
                            value: null, child: Text('Todos')),
                        ...options.entries.map((e) => DropdownMenuItem(
                            value: e.key,
                            child:
                                Text(e.value, overflow: TextOverflow.ellipsis)))
                      ],
                      onChanged: (v) => update(() => change(v)));
              return AlertDialog(
                  title: const Text('Filtrar lançamentos'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    choice(
                        'Conta ou cartão',
                        _filter.accountId,
                        {for (final a in app.accounts) a.id: a.name},
                        (v) => _filter.accountId = v),
                    choice(
                        'Categoria',
                        _filter.categoryId,
                        {for (final c in app.categories) c.id: c.name},
                        (v) => _filter.categoryId = v),
                    choice(
                        'Situação',
                        _filter.status,
                        {
                          'paid': 'Pago / recebido',
                          'pending': 'Pendente / previsto'
                        },
                        (v) => _filter.status = v),
                    choice(
                        'Origem',
                        _filter.source,
                        {
                          'manual': 'Manual',
                          'import': 'Importação',
                          'recurring': 'Recorrente',
                          'installment': 'Parcelamento'
                        },
                        (v) => _filter.source = v),
                    choice(
                        'Classe',
                        _filter.expenseClass,
                        {'normal': 'Normal', 'extraordinary': 'Pontual'},
                        (v) => _filter.expenseClass = v),
                    CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Somente parcelados'),
                        value: _filter.installmentsOnly,
                        onChanged: (v) =>
                            update(() => _filter.installmentsOnly = v!)),
                    TextButton.icon(
                        icon: const Icon(Icons.date_range),
                        label: Text(_filter.from == null
                            ? 'Escolher período'
                            : '${ptDate(_filter.from!)} a ${ptDate(_filter.to!)}'),
                        onPressed: () async {
                          final range = await showDateRangePicker(
                              context: ctx,
                              firstDate: DateTime(1900),
                              lastDate: DateTime(2200),
                              initialDateRange: _filter.from == null
                                  ? null
                                  : DateTimeRange(
                                      start: _filter.from!, end: _filter.to!));
                          if (range != null && ctx.mounted)
                            update(() {
                              _filter.from = range.start;
                              _filter.to = range.end;
                            });
                        }),
                    const Text('Valores na moeda original de cada lançamento.'),
                    TextField(
                        controller: min,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Valor mínimo')),
                    TextField(
                        controller: max,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration:
                            const InputDecoration(labelText: 'Valor máximo')),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(ctx).colorScheme.error)),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () {
                          update(() {
                            _filter = TransactionFilter();
                            min.clear();
                            max.clear();
                            error = null;
                          });
                        },
                        child: const Text('Limpar')),
                    FilledButton(
                        onPressed: () {
                          final low = min.text.trim().isEmpty
                              ? null
                              : parseMoney(min.text);
                          final high = max.text.trim().isEmpty
                              ? null
                              : parseMoney(max.text);
                          if ((min.text.trim().isNotEmpty && low == null) ||
                              (max.text.trim().isNotEmpty && high == null) ||
                              (low != null && low < 0) ||
                              (high != null && high < 0) ||
                              (low != null && high != null && low > high)) {
                            update(() => error =
                                'Informe valores válidos; o mínimo deve ser menor ou igual ao máximo.');
                            return;
                          }
                          _filter.minimum = low;
                          _filter.maximum = high;
                          applied = true;
                          Navigator.pop(ctx);
                        },
                        child: const Text('Aplicar'))
                  ]);
            }));
    min.dispose();
    max.dispose();
    if (!applied) _filter = previous;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final transactions = List<AppTransaction>.from(app.transactions)
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
              tooltip: 'Novo lançamento (Ctrl+N)',
              icon: const Icon(Icons.add),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const AddTransactionScreen()))),
          IconButton(
              tooltip: 'Filtros',
              onPressed: _filters,
              icon: const Icon(Icons.filter_alt_outlined))
        ],
        title: const Text('Transações',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: Builder(
        builder: (context) {
          final meta = app.transactionMetadata;
          final filtered = transactions.where((tx) {
            final m = meta[tx.id] ?? TransactionMetadata(transactionId: tx.id);
            if (!TransactionFilter.matchesType(tx, m, _type) ||
                !_filter.matches(tx, m)) return false;
            if (_query.trim().isEmpty) return true;
            final q = _query.toLowerCase().trim();
            final account = app.accountById(tx.accountId)?.name ?? '';
            final category = app.categoryLabel(tx);
            final subcategory = meta[tx.id]?.subcategory ?? '';
            return tx.description.toLowerCase().contains(q) ||
                tx.note.toLowerCase().contains(q) ||
                account.toLowerCase().contains(q) ||
                category.toLowerCase().contains(q) ||
                subcategory.toLowerCase().contains(q) ||
                DateFormat('dd/MM/yyyy').format(tx.date).contains(q);
          }).toList();

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _controller,
                  focusNode: widget.searchFocus,
                  autofocus: widget.autofocus,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'iFood, internet, Mercado Pago, 25/09...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _controller.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  children: [
                    _TypeChip(
                      label: 'Todos',
                      value: 'all',
                      current: _type,
                      onTap: (v) => setState(() => _type = v),
                    ),
                    _TypeChip(
                      label: 'Despesas',
                      value: 'expense',
                      current: _type,
                      onTap: (v) => setState(() => _type = v),
                    ),
                    _TypeChip(
                      label: 'Receitas',
                      value: 'income',
                      current: _type,
                      onTap: (v) => setState(() => _type = v),
                    ),
                    _TypeChip(
                        label: 'Neutros',
                        value: 'neutral',
                        current: _type,
                        onTap: (v) => setState(() => _type = v)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(children: [
                  Text(
                    '${filtered.length} resultado${filtered.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const SizedBox(width: 12),
                  if (filtered.isNotEmpty)
                    Expanded(child: _Totals(app: app, rows: filtered)),
                ]),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'Nenhum lançamento encontrado. Tente outro termo ou filtro.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : MediaQuery.sizeOf(context).width >= 900
                        ? DesktopTransactionTable(app: app, rows: filtered)
                        : _DayList(
                            app: app,
                            rows: filtered,
                            onOpen: (tx) async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AddTransactionScreen(
                                    existing: tx,
                                    initialType: tx.type,
                                  ),
                                ),
                              );
                              if (mounted) setState(() {});
                            },
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onTap;

  const _TypeChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: current == value,
        onSelected: (_) => onTap(value),
      ),
    );
  }
}

double _main(AppProvider app, AppTransaction t) => app.convertToMain(
    t.amount,
    t.currency.isNotEmpty
        ? t.currency
        : app.accountById(t.accountId)?.currency ?? app.settings.currency);

/// Counted income and spending of what is listed (neutral and pending out).
class _Totals extends StatelessWidget {
  final AppProvider app;
  final List<AppTransaction> rows;
  const _Totals({required this.app, required this.rows});
  @override
  Widget build(BuildContext context) {
    if (app.settings.hideBalance) return const SizedBox.shrink();
    var income = 0.0, expense = 0.0;
    for (final t in rows) {
      final m = app.transactionMetadata[t.id];
      if (FinanceRules.isNeutral(t, m) || m?.isPending == true) continue;
      if (t.type == 'income') income += _main(app, t);
      if (t.type == 'expense') expense += _main(app, t);
    }
    final style = Theme.of(context).textTheme.labelMedium;
    return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text.rich(TextSpan(style: style, children: [
          TextSpan(
              text: '+${formatAmount(income, app.settings.currency)}',
              style: TextStyle(
                  color: NexoTones.income(context),
                  fontWeight: FontWeight.w800)),
          const TextSpan(text: '   '),
          TextSpan(
              text: '−${formatAmount(expense, app.settings.currency)}',
              style: TextStyle(
                  color: NexoTones.expense(context),
                  fontWeight: FontWeight.w800)),
        ])));
  }
}

/// Statement grouped by day, like a bank app: day header with the net of
/// the day, then each movement with its category, account and status.
class _DayList extends StatelessWidget {
  final AppProvider app;
  final List<AppTransaction> rows;
  final void Function(AppTransaction) onOpen;
  const _DayList({required this.app, required this.rows, required this.onOpen});

  String _day(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return 'Hoje';
    if (day == today.subtract(const Duration(days: 1))) return 'Ontem';
    final label = DateFormat("EEE, d 'de' MMM", 'pt_BR').format(d);
    return day.year == today.year ? label : '$label de ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final items = <Object>[];
    DateTime? current;
    final net = <DateTime, double>{};
    for (final t in rows) {
      final day = DateTime(t.date.year, t.date.month, t.date.day);
      if (day != current) {
        items.add(day);
        current = day;
      }
      items.add(t);
      final m = app.transactionMetadata[t.id];
      if (!FinanceRules.isNeutral(t, m) && m?.isPending != true) {
        net[day] = (net[day] ?? 0) +
            (t.type == 'income' ? _main(app, t) : -_main(app, t));
      }
    }
    final theme = Theme.of(context);
    final hidden = app.settings.hideBalance;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DateTime) {
          final value = net[item] ?? 0;
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
            child: Row(children: [
              Expanded(
                  child: Text(_day(item),
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w800))),
              if (!hidden && value != 0)
                Text(
                    '${value > 0 ? '+' : '−'}${formatAmount(value.abs(), app.settings.currency)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFeatures: NexoTones.figures)),
            ]),
          );
        }
        final tx = item as AppTransaction;
        final account = app.accountById(tx.accountId);
        final category = app.categoryFor(tx);
        final m = app.transactionMetadata[tx.id];
        final neutral = FinanceRules.isNeutral(tx, m);
        final currency = tx.currency.isNotEmpty
            ? tx.currency
            : (account?.currency ?? app.settings.currency);
        final income = tx.type == 'income';
        final status = income && m?.isPending != true
            ? 'Recebido'
            : (m?.isOverdue == true
                ? 'Atrasado'
                : m?.status == 'pending'
                    ? 'Pendente'
                    : 'Pago');
        final color = neutral
            ? null
            : m?.isOverdue == true
                ? NexoTones.expense(context)
                : m?.isPending == true
                    ? NexoTones.warning(context)
                    : income
                        ? NexoTones.income(context)
                        : null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(18),
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              leading: neutral
                  ? CircleAvatar(
                      radius: 20,
                      backgroundColor: theme.colorScheme.surfaceContainerHigh,
                      child: const Icon(Icons.swap_horiz, size: 20))
                  : CategoryDot(category: category, size: 40),
              title: Text(
                tx.description.trim().isEmpty
                    ? (category?.name ?? 'Lançamento')
                    : tx.description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                [
                  if (account != null) account.name,
                  if (category != null && !neutral) category.name,
                  if ((m?.subcategory ?? '').isNotEmpty) m!.subcategory,
                  status,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                      hidden
                          ? '••••'
                          : '${income ? '+' : '-'}${formatAmount(tx.amount, currency)}',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: color,
                          fontFeatures: NexoTones.figures)),
                ),
              ),
              onTap: () => onOpen(tx),
            ),
          ),
        );
      },
    );
  }
}
