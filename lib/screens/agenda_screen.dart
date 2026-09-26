import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/billing_cycle.dart';
import '../theme/app_theme.dart';
import '../utils/finance_input.dart';
import 'add_transaction_screen.dart';
import 'card_invoice_screen.dart';
import 'recurring_detail_screen.dart';

class AgendaScreen extends StatelessWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    final now = DateTime.now();
    final horizon = DateTime(now.year, now.month + 3, now.day);
    final rows = <({
      DateTime date,
      String title,
      String detail,
      double amount,
      String currency,
      Widget page
    })>[];
    for (final tx in app.transactions) {
      final meta = app.transactionMetadata[tx.id];
      if (meta?.isPending != true) continue;
      final date = meta?.dueDate ?? tx.date;
      if (date.isAfter(horizon)) continue;
      final account = app.accountById(tx.accountId);
      rows.add((
        date: date,
        title: tx.description,
        detail:
            '${tx.type == 'income' ? 'Receita prevista' : 'Despesa pendente'} • ${account?.name ?? ''}',
        amount: tx.amount,
        currency: tx.currency.isEmpty
            ? account?.currency ?? app.settings.currency
            : tx.currency,
        page: AddTransactionScreen(existing: tx, initialType: tx.type)
      ));
    }
    for (final r in app.recurring) {
      if (r.nextDate.isAfter(horizon) ||
          (r.endDate != null && r.nextDate.isAfter(r.endDate!))) continue;
      final currency =
          app.accountById(r.accountId)?.currency ?? app.settings.currency;
      rows.add((
        date: r.nextDate,
        title: r.name,
        detail:
            '${r.paymentType == 'income' ? 'Receita recorrente' : r.recurringType == 'installment' ? 'Parcela' : 'Despesa fixa'} • ${app.accountById(r.accountId)?.name ?? ''}',
        amount: r.amount,
        currency: currency,
        page: RecurringDetailScreen(
            recurring: r, fmt: (v) => formatAmount(v, currency))
      ));
    }
    for (final card in app.accounts.where((a) => a.type == 'credit')) {
      final cycle = BillingCycle.forDate(now, card.statementDay, card.dueDay);
      if (cycle.due == null) continue;
      rows.add((
        date: cycle.due!,
        title: 'Fatura ${card.name}',
        detail: 'Consulte as compras e os pagamentos da fatura',
        amount: -card.balance.clamp(double.negativeInfinity, 0).toDouble(),
        currency: card.currency,
        page: CardInvoiceScreen(cardId: card.id)
      ));
    }
    rows.sort((a, b) => a.date.compareTo(b.date));
    return Scaffold(
        appBar: AppBar(title: const Text('Agenda financeira')),
        body: rows.isEmpty
            ? const Center(
                child: Text('Nenhum compromisso nos próximos 90 dias.'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final row = rows[i];
                  return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      title: Text(row.title),
                      subtitle: Text('${ptDate(row.date)} • ${row.detail}'),
                      trailing: Text(app.settings.hideBalance
                          ? '••••'
                          : formatAmount(row.amount, row.currency)),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => row.page)));
                }));
  }
}
