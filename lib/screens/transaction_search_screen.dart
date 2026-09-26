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

class TransactionSearchScreen extends StatefulWidget {
  const TransactionSearchScreen({super.key});

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
                        {'normal': 'Normal', 'extraordinary': 'Extraordinária'},
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
              tooltip: 'Filtros',
              onPressed: _filters,
              icon: const Icon(Icons.filter_alt_outlined))
        ],
        title: const Text('Buscar lançamentos',
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
            final category = app.categoryById(tx.categoryId)?.name ?? '';
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
                  autofocus: true,
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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${filtered.length} resultado${filtered.length == 1 ? '' : 's'}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
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
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final tx = filtered[index];
                          final account = app.accountById(tx.accountId);
                          final category = app.categoryById(tx.categoryId);
                          final txMeta = meta[tx.id];
                          final currency = tx.currency.isNotEmpty
                              ? tx.currency
                              : (account?.currency ?? app.settings.currency);
                          final status =
                              tx.type == 'income' && txMeta?.isPending != true
                                  ? 'Recebido'
                                  : (txMeta?.isOverdue == true
                                      ? 'Atrasado'
                                      : txMeta?.status == 'pending'
                                          ? 'Pendente'
                                          : 'Pago');

                          return Card(
                            child: ListTile(
                              title: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      tx.description.trim().isEmpty
                                          ? (category?.name ?? 'Lançamento')
                                          : tx.description,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                        app.settings.hideBalance
                                            ? '••••'
                                            : '${tx.type == 'income' ? '+' : '-'}${formatAmount(tx.amount, currency)}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800))
                                  ]),
                              subtitle: Text(
                                [
                                  DateFormat('dd/MM/yyyy').format(tx.date),
                                  if (account != null) account.name,
                                  if (category != null) category.name,
                                  if ((txMeta?.subcategory ?? '').isNotEmpty)
                                    txMeta!.subcategory,
                                  status,
                                ].join(' • '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () async {
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
                          );
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
