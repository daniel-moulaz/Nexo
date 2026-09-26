import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import 'add_transaction_screen.dart';

class TransactionSearchScreen extends StatefulWidget {
  const TransactionSearchScreen({super.key});

  @override
  State<TransactionSearchScreen> createState() => _TransactionSearchScreenState();
}

class _TransactionSearchScreenState extends State<TransactionSearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  String _type = 'all';

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
        title: const Text('Buscar lançamentos',
            style: TextStyle(fontWeight: FontWeight.w900)),
      ),
      body: FutureBuilder<Map<String, TransactionMetadata>>(
        future: TransactionMetadataService.instance
            .getForMany(transactions.map((e) => e.id)),
        builder: (context, snapshot) {
          final meta = snapshot.data ?? const <String, TransactionMetadata>{};
          final filtered = transactions.where((tx) {
            if (_type != 'all' && tx.type != _type) return false;
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
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                          final status = tx.type == 'income' && txMeta?.isPending != true
                              ? 'Recebido'
                              : (txMeta?.isOverdue == true
                                  ? 'Atrasado'
                                  : txMeta?.status == 'pending'
                                      ? 'Pendente'
                                      : 'Pago');

                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                child: Icon(tx.type == 'income'
                                    ? Icons.arrow_downward_rounded
                                    : Icons.arrow_upward_rounded),
                              ),
                              title: Text(
                                tx.description.trim().isEmpty
                                    ? (category?.name ?? 'Lançamento')
                                    : tx.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
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
                              trailing: Text(
                                '${tx.type == 'income' ? '+' : '-'}${formatAmount(tx.amount, currency)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: tx.type == 'income'
                                      ? Colors.green
                                      : Theme.of(context).colorScheme.error,
                                ),
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
