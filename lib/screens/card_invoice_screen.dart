import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/finance_rules.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';

class CardInvoiceScreen extends StatefulWidget {
  final String cardId;

  const CardInvoiceScreen({super.key, required this.cardId});

  @override
  State<CardInvoiceScreen> createState() => _CardInvoiceScreenState();
}

class _CardInvoiceScreenState extends State<CardInvoiceScreen> {
  Future<Map<String, TransactionMetadata>>? _metadata;

  DateTime _safeDate(int year, int month, int day) {
    final max = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, day.clamp(1, max));
  }

  ({DateTime start, DateTime end, DateTime? due}) _cycle(Account card) {
    final now = DateTime.now();
    final closeDay = card.statementDay ?? 1;
    final thisClose = _safeDate(now.year, now.month, closeDay);
    final DateTime start;
    final DateTime end;
    if (!now.isAfter(thisClose)) {
      end = thisClose;
      start = _safeDate(now.year, now.month - 1, closeDay)
          .add(const Duration(days: 1));
    } else {
      start = thisClose.add(const Duration(days: 1));
      end = _safeDate(now.year, now.month + 1, closeDay);
    }

    DateTime? due;
    if (card.dueDay != null) {
      final dueMonth = end.month == 12 ? 1 : end.month + 1;
      final dueYear = end.month == 12 ? end.year + 1 : end.year;
      due = _safeDate(dueYear, dueMonth, card.dueDay!);
    }
    return (start: start, end: end, due: due);
  }

  Future<void> _editSettings(Account card) async {
    final statementCtrl = TextEditingController(
      text: card.statementDay?.toString() ?? '',
    );
    final dueCtrl = TextEditingController(text: card.dueDay?.toString() ?? '');
    final limitCtrl = TextEditingController(
      text: card.creditLimit?.toStringAsFixed(2) ?? '',
    );

    final save = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Configurar fatura'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: statementCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dia de fechamento',
                hintText: 'Ex.: 20',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: dueCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Dia de vencimento',
                hintText: 'Ex.: 27',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: limitCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Limite do cartão'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );

    if (save != true || !mounted) return;
    final statement = int.tryParse(statementCtrl.text.trim());
    final due = int.tryParse(dueCtrl.text.trim());
    final limit = double.tryParse(limitCtrl.text.trim().replaceAll(',', '.'));
    if (statement == null || statement < 1 || statement > 31) {
      _snack('Informe um dia de fechamento entre 1 e 31.');
      return;
    }
    if (due == null || due < 1 || due > 31) {
      _snack('Informe um dia de vencimento entre 1 e 31.');
      return;
    }

    await context.read<AppProvider>().updateAccount(
          card.copyWith(
            statementDay: statement,
            dueDay: due,
            creditLimit: limit,
          ),
        );
    if (mounted) setState(() {});
  }

  Future<void> _payInvoice(Account card, double total) async {
    if (total <= 0) return;
    final app = context.read<AppProvider>();
    final linked = card.linkedAccountId == null
        ? null
        : app.accountById(card.linkedAccountId!);
    if (linked == null) {
      _snack(
        'Vincule uma conta bancária ao cartão na tela de Contas e cartões antes de registrar o pagamento.',
      );
      return;
    }

    final fromAmount = linked.currency == card.currency
        ? total
        : (app.convertBetween(total, card.currency, linked.currency) ?? total);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pagar fatura'),
        content: Text(
          'Registrar ${formatAmount(total, card.currency)} na fatura, saindo ${formatAmount(fromAmount, linked.currency)} de ${linked.name}?\n\nO pagamento será tratado como transferência e não será contado novamente como despesa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Registrar pagamento'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await app.addTransfer(
      fromId: linked.id,
      toId: card.id,
      fromAmount: fromAmount,
      toAmount: total,
      note: 'Pagamento da fatura ${card.name}',
    );
    if (!mounted) return;
    _snack('Pagamento registrado sem duplicar seus gastos.');
    setState(() {
      _metadata = null;
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final card = app.accountById(widget.cardId);
    if (card == null) {
      return const Scaffold(body: Center(child: Text('Cartão não encontrado.')));
    }

    final cycle = _cycle(card);
    final allCycleTx = app.transactions.where((t) =>
        t.accountId == card.id &&
        t.type == 'expense' &&
        !t.date.isBefore(cycle.start) &&
        !t.date.isAfter(cycle.end));
    _metadata ??= TransactionMetadataService.instance
        .getForMany(allCycleTx.map((e) => e.id));

    return FutureBuilder<Map<String, TransactionMetadata>>(
      future: _metadata,
      builder: (context, snapshot) {
        final meta = snapshot.data ?? const <String, TransactionMetadata>{};
        final purchases = allCycleTx
            .where((t) => !FinanceRules.isNeutral(t, meta[t.id]))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final total = purchases.fold<double>(0, (s, t) => s + t.amount);
        final freeLimit = card.creditLimit == null
            ? null
            : (card.creditLimit! - total).clamp(0.0, double.infinity).toDouble();

        return Scaffold(
          appBar: AppBar(
            title: Text(card.name,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              IconButton(
                tooltip: 'Configurar fatura',
                onPressed: () => _editSettings(card),
                icon: const Icon(Icons.tune_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Color(card.colorValue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fatura atual'),
                    const SizedBox(height: 4),
                    Text(
                      formatAmount(total, card.currency),
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Período ${DateFormat('dd/MM').format(cycle.start)} a ${DateFormat('dd/MM').format(cycle.end)}',
                    ),
                    if (cycle.due != null)
                      Text('Vencimento ${DateFormat('dd/MM/yyyy').format(cycle.due!)}'),
                    if (freeLimit != null)
                      Text('Limite disponível ${formatAmount(freeLimit, card.currency)}'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (card.statementDay == null || card.dueDay == null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Configure fechamento e vencimento'),
                    subtitle: const Text(
                      'Esses dias são necessários para calcular a fatura corretamente.',
                    ),
                    onTap: () => _editSettings(card),
                  ),
                ),
              if (total > 0) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => _payInvoice(card, total),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Registrar pagamento da fatura'),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Compras da fatura',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              if (purchases.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 36),
                  child: Center(child: Text('Nenhuma compra nesta fatura.')),
                )
              else
                ...purchases.map((tx) {
                  final category = app.categoryById(tx.categoryId);
                  final txMeta = meta[tx.id];
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.shopping_bag_outlined),
                      ),
                      title: Text(
                        tx.description.trim().isEmpty
                            ? (category?.name ?? 'Compra')
                            : tx.description,
                      ),
                      subtitle: Text([
                        DateFormat('dd/MM/yyyy').format(tx.date),
                        if ((txMeta?.subcategory ?? '').isNotEmpty)
                          txMeta!.subcategory,
                        if ((txMeta?.installmentLabel ?? '').isNotEmpty)
                          'Parcela ${txMeta!.installmentLabel}',
                      ].join(' • ')),
                      trailing: Text(
                        formatAmount(tx.amount, card.currency),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
