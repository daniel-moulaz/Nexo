import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../providers/app_provider.dart';
import '../services/card_invoice_service.dart';
import '../services/finance_rules.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import '../services/billing_cycle.dart';
import '../utils/finance_input.dart';

class CardInvoiceScreen extends StatefulWidget {
  final String cardId;
  final DateTime? initialCycleEnd;

  const CardInvoiceScreen(
      {super.key, required this.cardId, this.initialCycleEnd});

  @override
  State<CardInvoiceScreen> createState() => _CardInvoiceScreenState();
}

class _CardInvoiceScreenState extends State<CardInvoiceScreen> {
  Future<Map<String, TransactionMetadata>>? _metadata;
  int _monthOffset = 0;
  bool _paying = false;

  ({DateTime start, DateTime end, DateTime? due}) _cycle(Account card) {
    final initial = widget.initialCycleEnd;
    final cycle = BillingCycle.forDate(
        BillingCycle.date(
            initial?.year ?? DateTime.now().year,
            (initial?.month ?? DateTime.now().month) + _monthOffset,
            initial?.day ?? DateTime.now().day),
        card.statementDay,
        card.dueDay);
    return (start: cycle.start, end: cycle.end, due: cycle.due);
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
    final limit = parseMoney(limitCtrl.text);
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

  Future<void> _payInvoice(
    Account card,
    DateTime cycleEnd,
    double remaining,
  ) async {
    if (remaining <= 0 || _paying) return;
    final amountCtrl = TextEditingController(
        text: remaining.toStringAsFixed(2).replaceAll('.', ','));
    final selected = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('Pagamento total ou parcial'),
              content: TextField(
                  controller: amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                      labelText: 'Valor a pagar',
                      helperText:
                          'Em aberto: ${formatAmount(remaining, card.currency)}')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () {
                      final value = parseMoney(amountCtrl.text);
                      if (value == null ||
                          value <= 0 ||
                          value > remaining + 0.005) {
                        _snack(
                            'Informe um valor maior que zero e até o total em aberto.');
                        return;
                      }
                      Navigator.pop(ctx, value);
                    },
                    child: const Text('Continuar'))
              ],
            ));
    if (selected == null || !mounted) return;
    remaining = selected;
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
        ? remaining
        : (app.convertBetween(remaining, card.currency, linked.currency) ??
            remaining);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pagar fatura'),
        content: Text(
          'Registrar ${formatAmount(remaining, card.currency)} na fatura, saindo ${formatAmount(fromAmount, linked.currency)} de ${linked.name}?\n\nO pagamento será tratado como transferência e não será contado novamente como despesa.',
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

    setState(() => _paying = true);
    try {
      await app.addTransfer(
          fromId: linked.id,
          toId: card.id,
          fromAmount: fromAmount,
          toAmount: remaining,
          invoiceCycleEnd: cycleEnd,
          note: 'Pagamento da fatura ${card.name}');
    } catch (_) {
      _snack(
          'Não foi possível pagar. Atualize a fatura e confira o valor e a conta.');
      return;
    } finally {
      if (mounted) setState(() => _paying = false);
    }
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
      return const Scaffold(
          body: Center(child: Text('Cartão não encontrado.')));
    }

    final cycle = _cycle(card);
    final allCycleTx = app.transactions.where((t) =>
        t.accountId == card.id &&
        !t.date.isBefore(cycle.start) &&
        t.date.isBefore(cycle.end.add(const Duration(days: 1))));
    _metadata ??= TransactionMetadataService.instance
        .getForMany(allCycleTx.map((e) => e.id));

    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        _metadata!,
        CardInvoiceService.instance.paidForCycle(card.id, cycle.end),
      ]),
      builder: (context, snapshot) {
        final values = snapshot.data;
        final meta = values == null
            ? const <String, TransactionMetadata>{}
            : values[0] as Map<String, TransactionMetadata>;
        final alreadyPaid = values == null ? 0.0 : values[1] as double;
        final purchases = allCycleTx
            .where((t) =>
                !FinanceRules.isNeutral(t, meta[t.id]) ||
                meta[t.id]?.source == 'opening_balance')
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final total = purchases.fold<double>(
            0, (s, t) => s + (t.type == 'income' ? -t.amount : t.amount));
        final remaining =
            (total - alreadyPaid).clamp(0.0, double.infinity).toDouble();
        final freeLimit = card.creditLimit == null
            ? null
            : (card.creditLimit! +
                    card.balance.clamp(double.negativeInfinity, 0))
                .clamp(0.0, double.infinity)
                .toDouble();

        return Scaffold(
          appBar: AppBar(
            title: Text(card.name,
                style: const TextStyle(fontWeight: FontWeight.w900)),
            actions: [
              IconButton(
                  tooltip: 'Fatura anterior',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() {
                        _monthOffset--;
                        _metadata = null;
                      })),
              IconButton(
                  tooltip: 'Próxima fatura',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() {
                        _monthOffset++;
                        _metadata = null;
                      })),
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
                      style:
                          Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Período ${DateFormat('dd/MM').format(cycle.start)} a ${DateFormat('dd/MM').format(cycle.end)}',
                    ),
                    if (cycle.due != null)
                      Text(
                          'Vencimento ${DateFormat('dd/MM/yyyy').format(cycle.due!)}'),
                    if (alreadyPaid > 0)
                      Text(
                          'Já pago ${formatAmount(alreadyPaid, card.currency)}'),
                    Text(
                      remaining <= 0
                          ? 'Situação: paga'
                          : 'Em aberto ${formatAmount(remaining, card.currency)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (freeLimit != null)
                      Text(
                          'Limite disponível ${formatAmount(freeLimit, card.currency)}'),
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
              if (remaining > 0) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _paying
                      ? null
                      : () => _payInvoice(card, cycle.end, remaining),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(
                    alreadyPaid > 0
                        ? 'Pagar restante da fatura'
                        : 'Registrar pagamento da fatura',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                'Compras e créditos da fatura',
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
                        '${tx.type == 'income' ? '− ' : ''}${formatAmount(tx.amount, card.currency)}',
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
