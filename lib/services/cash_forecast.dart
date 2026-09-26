import '../models/models.dart';
import 'billing_cycle.dart';
import 'finance_rules.dart';
import 'transaction_metadata_service.dart';

class ForecastEvent {
  final DateTime date;
  final String title, accountId, kind, id, currency;
  final double amount; // Signed cash movement; zero for informational events.
  final DateTime? cycleEnd;
  const ForecastEvent(
      {required this.date,
      required this.title,
      required this.accountId,
      required this.kind,
      required this.id,
      required this.currency,
      required this.amount,
      this.cycleEnd});
}

class CashForecast {
  final double current, projected;
  final List<ForecastEvent> events;
  final List<String> warnings;
  const CashForecast(this.current, this.projected, this.events, this.warnings);

  /// Read-only projection: does not create transactions or recalculate balances.
  static CashForecast calculate(
      {required DateTime now,
      required DateTime until,
      required List<Account> accounts,
      required List<AppTransaction> transactions,
      required List<RecurringPayment> recurring,
      required Map<String, TransactionMetadata> metadata,
      required List<Map<String, dynamic>> invoicePayments,
      required double Function(double, String) convert}) {
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
    final end = day(until);
    final today = day(now);
    final byId = {for (final a in accounts) a.id: a};
    bool cash(Account a) =>
        !a.isGold && a.type != 'credit' && !a.excludeFromTotal;
    final current = accounts
        .where(cash)
        .fold<double>(0, (sum, a) => sum + convert(a.balance, a.currency));
    final events = <ForecastEvent>[];
    final warnings = <String>[];
    final invoices =
        <String, ({Account card, BillingCycle cycle, double amount})>{};
    String key(String id, DateTime d) =>
        '$id|${d.toIso8601String().substring(0, 10)}';
    void cardPurchase(Account a, DateTime date, double amount) {
      final cycle = BillingCycle.forDate(date, a.statementDay, a.dueDay);
      if (cycle.due == null) return;
      final k = key(a.id, cycle.end);
      invoices[k] =
          (card: a, cycle: cycle, amount: (invoices[k]?.amount ?? 0) + amount);
    }

    for (final tx in transactions) {
      final a = byId[tx.accountId];
      if (a == null) continue;
      final m = metadata[tx.id] ?? TransactionMetadata(transactionId: tx.id);
      final signed = tx.type == 'income' ? tx.amount : -tx.amount;
      if (a.type == 'credit') {
        if (!FinanceRules.isNeutral(tx, m) || m.source == 'opening_balance') {
          final currency = tx.currency.isEmpty ? a.currency : tx.currency;
          final rate = convert(1, a.currency);
          cardPurchase(
              a,
              tx.date,
              currency == a.currency || rate == 0
                  ? -signed
                  : convert(-signed, currency) / rate);
        }
      } else if (m.isPending && m.affectsBalance && cash(a)) {
        final date = day(m.dueDate ?? tx.date);
        if (!date.isAfter(end))
          events.add(ForecastEvent(
              date: date,
              title: tx.description,
              accountId: a.id,
              kind: 'transaction',
              id: tx.id,
              currency: tx.currency.isEmpty ? a.currency : tx.currency,
              amount: signed));
      }
    }
    final ids = transactions.map((t) => t.id).toSet();
    for (final original in recurring) {
      final a = byId[original.accountId];
      if (a == null || (!cash(a) && a.type != 'credit')) continue;
      if (original.freqVal < 1) {
        warnings.add('Revise a frequência de ${original.name}.');
        continue;
      }
      final r = RecurringPayment.fromMap(original.toMap(),
          skippedOccurrences: original.skippedOccurrences);
      if (r.hasSkippedInstallments) {
        for (final missed in r.skippedOccurrences) {
          if (day(missed.date).isAfter(end) || ids.contains(missed.id)) continue;
          final amount = r.paymentType == 'income' ? missed.amount : -missed.amount;
          if (a.type == 'credit') {
            cardPurchase(a, missed.date, -amount);
          } else {
            events.add(ForecastEvent(date: day(missed.date), title: r.name,
                accountId: a.id, kind: 'recurring', id: r.id,
                currency: a.currency, amount: amount));
          }
        }
      }
      var count = 0;
      while (!day(r.nextDate).isAfter(end) &&
          (r.endDate == null || !day(r.nextDate).isAfter(day(r.endDate!)))) {
        if (++count > 3660) {
          warnings.add('Revise as ocorrências antigas de ${r.name}.');
          break;
        }
        final id = 'recurring:${r.id}:${r.nextDate.toIso8601String()}';
        if (!ids.contains(id)) {
          final amount = r.paymentType == 'income' ? r.amount : -r.amount;
          if (a.type == 'credit') {
            cardPurchase(a, r.nextDate, -amount);
          } else {
            events.add(ForecastEvent(
                date: day(r.nextDate),
                title: r.name,
                accountId: a.id,
                kind: 'recurring',
                id: r.id,
                currency: a.currency,
                amount: amount));
          }
        }
        final next = r.calcNextDate();
        if (!next.isAfter(r.nextDate)) break;
        r.nextDate = next;
      }
    }
    for (final a
        in accounts.where((a) => a.type == 'credit' && !a.excludeFromTotal)) {
      if (a.dueDay == null)
        warnings
            .add('${a.name}: configure o vencimento para incluir a fatura.');
      if (a.statementDay == null)
        warnings.add('${a.name}: sem fechamento, usamos o mês civil.');
      if (a.statementDay != null) {
        final cycle = BillingCycle.forDate(today, a.statementDay, a.dueDay);
        if (!cycle.end.isAfter(end))
          events.add(ForecastEvent(
              date: cycle.end,
              title: 'Fechamento ${a.name}',
              accountId: a.id,
              kind: 'closing',
              id: a.id,
              currency: a.currency,
              amount: 0,
              cycleEnd: cycle.end));
      }
    }
    final paid = <String, double>{};
    for (final p in invoicePayments) {
      final k = '${p['card_id']}|${p['cycle_end']}';
      paid[k] = (paid[k] ?? 0) + (p['amount'] as num).toDouble();
    }
    for (final entry in invoices.entries) {
      final inv = entry.value;
      if (inv.card.excludeFromTotal || inv.cycle.due!.isAfter(end)) continue;
      final remaining = (inv.amount - (paid[entry.key] ?? 0))
          .clamp(0.0, double.infinity)
          .toDouble();
      if (remaining < 0.005) continue;
      final linked = byId[inv.card.linkedAccountId];
      if (linked != null && !cash(linked)) {
        warnings.add(
            '${inv.card.name}: pagamento previsto em conta fora do saldo disponível.');
        continue;
      }
      events.add(ForecastEvent(
          date: inv.cycle.due!,
          title: 'Fatura ${inv.card.name}',
          accountId: inv.card.id,
          kind: 'invoice',
          id: inv.card.id,
          currency: inv.card.currency,
          amount: -remaining,
          cycleEnd: inv.cycle.end));
    }
    events.sort((a, b) => a.date.compareTo(b.date));
    return CashForecast(
        current,
        current +
            events.fold<double>(
                0, (sum, e) => sum + convert(e.amount, e.currency)),
        events,
        warnings.toSet().toList());
  }
}
