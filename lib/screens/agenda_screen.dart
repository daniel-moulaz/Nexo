import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../database/db_helper.dart';
import '../providers/app_provider.dart';
import '../services/cash_forecast.dart';
import '../services/transaction_metadata_service.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import 'add_transaction_screen.dart';
import 'card_invoice_screen.dart';
import 'recurring_detail_screen.dart';

class AgendaScreen extends StatefulWidget {
  const AgendaScreen({super.key});
  @override
  State<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends State<AgendaScreen> {
  int _days = 7;
  bool _busy = false;
  Future<List<Map<String, dynamic>>> _payments() async =>
      (await DBHelper.database).query('card_invoice_payments');

  Future<void> _act(ForecastEvent event, String action) async {
    final app = context.read<AppProvider>();
    if (action == 'edit') {
      Widget? page;
      if (event.kind == 'transaction') {
        final tx = app.transactions.where((t) => t.id == event.id).firstOrNull;
        if (tx != null)
          page = AddTransactionScreen(existing: tx, initialType: tx.type);
      } else if (event.kind == 'recurring') {
        final r = app.recurring.where((r) => r.id == event.id).firstOrNull;
        if (r != null)
          page = RecurringDetailScreen(
              recurring: r, fmt: (v) => formatAmount(v, event.currency));
      } else {
        page = CardInvoiceScreen(
            cardId: event.id, initialCycleEnd: event.cycleEnd);
      }
      if (page != null)
        await Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
      if (mounted) setState(() {});
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(action == 'skip'
                    ? 'Pular ocorrência?'
                    : 'Confirmar pagamento ou recebimento?'),
                content: Text('${event.title}\n${ptDate(event.date)}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Confirmar'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (event.kind == 'recurring') {
        final r = app.recurring.firstWhere((r) => r.id == event.id);
        if (r.nextDate.year != event.date.year ||
            r.nextDate.month != event.date.month ||
            r.nextDate.day != event.date.day) return;
        if (action == 'skip') {
          await app.skipNextRecurring(r);
        } else {
          await app.markRecurringPaid(r);
        }
      } else {
        final tx = app.transactions.firstWhere((t) => t.id == event.id);
        final meta = app.transactionMetadata[tx.id] ??
            TransactionMetadata(transactionId: tx.id);
        if (meta.isPending)
          await app.updateTransaction(tx, tx,
              metadata: TransactionMetadata.fromMap(
                  {...meta.toMap(), 'status': 'paid'}));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Não foi possível concluir. Revise o lançamento e tente novamente.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final until = _days == -1
        ? DateTime(now.year, now.month + 1, 0)
        : today.add(Duration(days: _days));
    String money(double v) => app.settings.hideBalance
        ? '••••'
        : formatAmount(v, app.settings.currency);
    return Scaffold(
        appBar: AppBar(title: const Text('Agenda e previsão')),
        body: FutureBuilder<List<Map<String, dynamic>>>(
            future: _payments(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Center(
                    child: Text(
                        'Não foi possível carregar a previsão. Reabra a agenda.'));
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());
              final forecast = CashForecast.calculate(
                  now: now,
                  until: until,
                  accounts: app.accounts,
                  transactions: app.transactions,
                  recurring: app.recurring,
                  metadata: app.transactionMetadata,
                  invoicePayments: snapshot.data!,
                  convert: app.convertToMain);
              return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Wrap(spacing: 8, children: [
                      for (final e in {
                        0: 'Hoje',
                        7: '7 dias',
                        15: '15 dias',
                        30: '30 dias',
                        -1: 'Este mês'
                      }.entries)
                        ChoiceChip(
                            label: Text(e.value),
                            selected: _days == e.key,
                            onSelected: _busy
                                ? null
                                : (_) => setState(() => _days = e.key))
                    ]),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      'Saldo atual: ${money(forecast.current)}'),
                                  const SizedBox(height: 8),
                                  Text('Previsto até ${ptDate(until)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                  FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(money(forecast.projected),
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                  color: forecast.projected < 0
                                                      ? Theme.of(context)
                                                          .colorScheme
                                                          .error
                                                      : null))),
                                  const SizedBox(height: 8),
                                  const ExpansionTile(
                                      tilePadding: EdgeInsets.zero,
                                      title: Text('Como calculamos'),
                                      children: [
                                        Text(
                                            'Saldo atual + receitas previstas − compromissos cadastrados, incluindo atrasados e faturas após pagamentos parciais. Não inclui novos gastos não cadastrados. Usa as cotações disponíveis no app; não é dinheiro disponível.')
                                      ]),
                                  for (final warning in forecast.warnings)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(warning)),
                                ]))),
                    if (forecast.events.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Nenhum compromisso neste período.')),
                    for (final event in forecast.events)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${ptDate(event.date)}${event.date.isBefore(today) ? ' • Atrasado' : ''}',
                                        style: TextStyle(
                                            color: event.date.isBefore(today)
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .error
                                                : null)),
                                    Text(event.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Text(app
                                            .accountById(event.accountId)
                                            ?.name ??
                                        ''),
                                    if (event.kind != 'closing')
                                      Text(app.settings.hideBalance
                                          ? '••••'
                                          : '${event.amount >= 0 ? '+' : '−'} ${formatAmount(event.amount.abs(), event.currency)}'),
                                    Wrap(spacing: 8, children: [
                                      TextButton(
                                          onPressed: _busy
                                              ? null
                                              : () => _act(event, 'edit'),
                                          child: Text(event.kind == 'invoice' ||
                                                  event.kind == 'closing'
                                              ? 'Ver fatura'
                                              : 'Editar / detalhes')),
                                      if (event.kind == 'transaction' ||
                                          (event.kind == 'recurring' &&
                                              app.recurring.any((r) =>
                                                  r.id == event.id &&
                                                  r.nextDate.year ==
                                                      event.date.year &&
                                                  r.nextDate.month ==
                                                      event.date.month &&
                                                  r.nextDate.day ==
                                                      event.date.day))) ...[
                                        TextButton(
                                            onPressed: _busy
                                                ? null
                                                : () => _act(event, 'pay'),
                                            child: Text(event.amount >= 0
                                                ? 'Receber'
                                                : 'Pagar')),
                                        if (event.kind == 'recurring')
                                          TextButton(
                                              onPressed: _busy
                                                  ? null
                                                  : () => _act(event, 'skip'),
                                              child: const Text('Pular')),
                                      ],
                                    ])
                                  ]))),
                  ]);
            }));
  }
}
