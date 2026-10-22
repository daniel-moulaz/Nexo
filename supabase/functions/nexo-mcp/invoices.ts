// Credit card invoices from the synced ledger, with the app's rule
// (lib/services/billing_cycle.dart): a purchase made on the closing day
// ("melhor dia de compra") already belongs to the next invoice; payments are
// keyed by the closing date.
import { cents, day, isNeutral, type Ledger, meta, metadataIndex, money, num, type Row, text } from "./finance.ts";

const pad = (n: number) => String(n).padStart(2, "0");
const iso = (y: number, m: number, d: number) => {
  const base = new Date(Date.UTC(y, m - 1, 1));
  const last = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth() + 1, 0)).getUTCDate();
  return `${base.getUTCFullYear()}-${pad(base.getUTCMonth() + 1)}-${pad(Math.min(Math.max(d, 1), last))}`;
};
const parts = (s: string) => s.split("-").map(Number) as [number, number, number];
const addDays = (s: string, n: number) => {
  const [y, m, d] = parts(s);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
};

export interface Cycle { start: string; end: string; due: string | null }

export function cycleFor(date: string, closingDay: number | null, dueDay: number | null): Cycle {
  const [y, m] = parts(date);
  const dueAfter = (end: string) => {
    if (dueDay == null) return null;
    const [ey, em] = parts(end);
    const due = iso(ey, em, dueDay);
    return due > end ? due : iso(ey, em + 1, dueDay);
  };
  if (closingDay == null) {
    const end = iso(y, m, 31);
    return { start: iso(y, m, 1), end, due: dueAfter(end) };
  }
  let end = iso(y, m, closingDay);
  if (date >= end) end = iso(y, m + 1, closingDay);
  const [ey, em] = parts(end);
  return { start: iso(ey, em - 1, closingDay), end, due: dueAfter(end) };
}

/// Recent and current invoices of each credit card, newest first.
export function cardInvoices(l: Ledger, today: string, cardId?: string) {
  const metas = metadataIndex(l);
  const out = [];
  for (const card of l.accounts.filter((a) => a.type === "credit" && (!cardId || a.id === cardId))) {
    const closing = typeof card.statement_day === "number" ? card.statement_day : null;
    const dueDay = typeof card.due_day === "number" ? card.due_day : null;
    const byEnd = new Map<string, { cycle: Cycle; total: number; paid: number }>();
    const slot = (c: Cycle) => byEnd.get(c.end) ?? byEnd.set(c.end, { cycle: c, total: 0, paid: 0 }).get(c.end)!;
    for (const tx of l.transactions) {
      if (tx.account_id !== card.id) continue;
      const m = meta(metas.get(text(tx.id)));
      if (isNeutral(tx, m) && m.source !== "opening_balance") continue;
      const s = slot(cycleFor(day(text(tx.date)), closing, dueDay));
      s.total += (tx.type === "income" ? -1 : 1) * cents(num(tx.amount));
    }
    for (const p of (l.invoicePayments ?? []) as Row[]) {
      if (p.card_id !== card.id) continue;
      const end = text(p.cycle_end).slice(0, 10);
      const s = byEnd.get(end) ?? slot({ ...cycleFor(addDays(end, -1), closing, dueDay) });
      s.paid += cents(num(p.amount));
    }
    const current = cycleFor(today, closing, dueDay);
    slot(current);
    const invoices = [...byEnd.values()]
      .filter((s) => s.cycle.end >= addDays(today, -100))
      .sort((a, b) => b.cycle.end.localeCompare(a.cycle.end))
      .slice(0, 4)
      .map(({ cycle, total, paid }) => {
        const remaining = Math.max(total - paid, 0);
        const closed = today >= cycle.end;
        const status = !closed ? "aberta"
          : remaining === 0 ? "paga"
          : cycle.due && today > cycle.due ? "atrasada" : "fechada";
        return {
          closing_date: cycle.end, due_date: cycle.due ?? undefined,
          purchases_from: cycle.start, purchases_until: addDays(cycle.end, -1),
          total: money(total), paid: money(paid), remaining: money(remaining), status,
        };
      });
    const limit = typeof card.credit_limit === "number" ? cents(card.credit_limit) : null;
    const owed = invoices.reduce((s, i) => s + cents(i.remaining), 0);
    out.push({
      card_id: text(card.id), card: text(card.name),
      closing_day: closing ?? undefined, due_day: dueDay ?? undefined,
      credit_limit: limit == null ? undefined : money(limit),
      limit_used_percent: limit ? Math.round((owed / limit) * 100) : undefined,
      invoices,
    });
  }
  return {
    cards: out,
    note: "Compras feitas no dia do fechamento entram na fatura seguinte. Pagar fatura: pay_card_invoice (invoice closed = a fechada mais recente).",
  };
}
