import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../services/finance_rules.dart';
import '../utils/finance_input.dart';
import '../theme/app_theme.dart';
import 'agenda_screen.dart';
import 'add_transaction_screen.dart';
import 'card_invoice_screen.dart';
import 'loans_screen.dart';
import 'loan_detail_screen.dart';
import 'recurring_detail_screen.dart';
import 'recurring_screen.dart';
import 'lended_screen.dart';

/// Navigation over existing records; never adds unrelated debt sources together.
class DebtOverviewScreen extends StatelessWidget {
  const DebtOverviewScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppProvider>();
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    String money(double v, String currency) =>
        app.settings.hideBalance ? '••••' : formatAmount(v, currency);
    final cards = app.accounts.where((a) => a.type == 'credit');
    final loans = app.loans.where((l) => !l.isSettled);
    final installments = app.recurring.where((r) =>
        r.paymentType == 'expense' &&
        r.recurringType == 'installment' &&
        r.canComplete);
    final pending = app.transactions
        .where((t) =>
            t.type == 'expense' &&
            app.transactionMetadata[t.id]?.isPending == true &&
            app.accountById(t.accountId)?.type != 'credit' &&
            !FinanceRules.isNeutral(t, app.transactionMetadata[t.id]))
        .toList()
      ..sort((a, b) => (app.transactionMetadata[a.id]?.dueDate ?? a.date)
          .compareTo(app.transactionMetadata[b.id]?.dueDate ?? b.date));
    Widget section(String title, String description, List<Widget> children,
            String action, VoidCallback onTap) =>
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(description),
                      ...children,
                      TextButton(onPressed: onTap, child: Text(action)),
                    ])));
    return Scaffold(
        appBar: AppBar(title: const Text('Dívidas e compromissos')),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const Text('O que falta pagar',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                  'Veja cada origem e abra os detalhes. Faturas, empréstimos e parcelas podem representar o mesmo compromisso; por isso não somamos tudo em um total único.'),
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_note),
                  title: const Text('Quando vence e como fica meu saldo?'),
                  subtitle: const Text(
                      'Agenda com previsão de caixa e vencimentos cadastrados'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(const AgendaScreen())),
              section(
                  'Cartões',
                  'Dívida atual por cartão, já descontados os pagamentos registrados.',
                  [
                    if (cards.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Nenhum cartão cadastrado.')),
                    for (final c in cards)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.name),
                          subtitle: Text(
                              'Em aberto: ${money((-c.balance).clamp(0.0, double.infinity), c.currency)}${c.excludeFromTotal ? ' • fora do saldo geral' : ''}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(CardInvoiceScreen(cardId: c.id))),
                  ],
                  'Ver próximos vencimentos',
                  () => open(const AgendaScreen())),
              section(
                  'Empréstimos',
                  'Restante calculado a partir do contrato e dos pagamentos registrados.',
                  [
                    if (loans.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Nenhum empréstimo em aberto.')),
                    for (final l in loans)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(l.name),
                          subtitle: Text(
                              'Falta ${money(app.loanRemaining(l), l.currency)}\nPago ${money(app.loanTotalPaid(l), l.currency)} • fim do contrato ${ptDate(l.endDate)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(LoanDetailScreen(loan: l))),
                  ],
                  'Gerenciar empréstimos e quitados',
                  () => open(const LoansScreen())),
              section(
                  'Parcelamentos recorrentes',
                  'Cronogramas cadastrados em Recorrentes. Compras já lançadas no cartão estão na fatura.',
                  [
                    if (installments.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text(
                              'Nenhum parcelamento recorrente em aberto.')),
                    for (final r in installments)
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(r.name),
                          subtitle: Text(
                              '${r.paidPayments} parcelas pagas${r.remainingPayments == null ? '' : ' • ${r.remainingPayments} restantes'}\nPróxima: ${ptDate(r.nextActionDate)} • ${money(r.nextActionAmount, app.accountById(r.accountId)?.currency ?? app.settings.currency)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(RecurringDetailScreen(
                              recurring: r,
                              fmt: (v) => money(
                                  v,
                                  app.accountById(r.accountId)?.currency ??
                                      app.settings.currency)))),
                  ],
                  'Ver recorrentes e histórico',
                  () => open(const RecurringScreen())),
              section(
                  'Despesas pendentes em conta',
                  'Ainda não debitadas do saldo atual. Transferências e pagamentos de fatura ficam fora desta lista.',
                  [
                    if (pending.isEmpty)
                      const Padding(
                          padding: EdgeInsets.all(12),
                          child: Text('Nenhuma despesa pendente em conta.')),
                    for (final t in pending.take(30))
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(t.description),
                          subtitle: Text(
                              '${ptDate(app.transactionMetadata[t.id]?.dueDate ?? t.date)} • ${money(t.amount, t.currency.isEmpty ? app.accountById(t.accountId)?.currency ?? app.settings.currency : t.currency)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => open(AddTransactionScreen(existing: t))),
                    if (pending.length > 30)
                      const Text(
                          'Primeiros 30 itens; veja os demais na Agenda.'),
                  ],
                  'Ver agenda completa',
                  () => open(const AgendaScreen())),
              ListTile(
                  title: const Text('Dinheiro emprestado a pessoas'),
                  subtitle:
                      const Text('Acompanhar valores a receber e devoluções'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => open(const LendedScreen())),
            ]));
  }
}
