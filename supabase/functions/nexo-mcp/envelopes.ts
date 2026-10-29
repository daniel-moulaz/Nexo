// "Por tipo de gasto" (Orçamento): the six kinds of spending of the AUVP
// method, mirroring lib/services/envelopes.dart (a test compares ids, names
// and default shares). Planning only: nothing here moves money.
import { cents, currencyOf, day, isNeutral, type Ledger, meta, metadataIndex, money, num, text } from "./finance.ts";

export interface EnvelopeDef { id: string; name: string; defaultShare: number; hint: string }

export const envelopes: EnvelopeDef[] = [
  { id: "fixed", name: "Custos fixos", defaultShare: 30, hint: "O que precisa pagar para viver: aluguel, luz, água, internet, mercado, plano de saúde." },
  { id: "comfort", name: "Conforto", defaultShare: 15, hint: "Melhora a rotina sem ser essencial: streaming, academia, delivery." },
  { id: "goals", name: "Metas", defaultShare: 15, hint: "O que guarda para um objetivo com prazo: viagem, entrada, troca de carro." },
  { id: "pleasures", name: "Prazeres", defaultShare: 10, hint: "Existe só pelo prazer: jantar fora, bar, presente, hobby." },
  { id: "knowledge", name: "Conhecimento", defaultShare: 5, hint: "Investe em você: cursos, livros, mentoria, certificação." },
  { id: "freedom", name: "Liberdade financeira", defaultShare: 25, hint: "O que investe para construir patrimônio: aportes e aplicações." },
];

export const envelopeById = (id: unknown) => envelopes.find((e) => e.id === id);

/// The month against the shares, as the Orçamento screen computes it:
/// expenses of each kind's categories (pending included, transfers and
/// adjustments out), investment purchases in Liberdade financeira and goal
/// deposits in Metas. Other currencies are reported apart, never converted.
export function spendingTypes(l: Ledger, month: string, shares: Record<string, number>, referenceIncome: number) {
  const from = `${month}-01`;
  const [y, m] = month.split("-").map(Number);
  const to = new Date(Date.UTC(y, m, 1)).toISOString().slice(0, 10); // exclusive
  const inMonth = (iso: string) => day(iso) >= from && day(iso) < to;
  const metas = metadataIndex(l);
  const byCategory = new Map<string, number>();
  const unconverted: Record<string, number> = {};
  for (const t of l.transactions) {
    if (t.type !== "expense" || !inMonth(text(t.date))) continue;
    if (isNeutral(t, meta(metas.get(text(t.id))))) continue;
    const currency = currencyOf(l, t);
    if (currency !== l.mainCurrency) {
      unconverted[currency] = (unconverted[currency] ?? 0) + cents(num(t.amount));
      continue;
    }
    const c = text(t.category_id);
    byCategory.set(c, (byCategory.get(c) ?? 0) + cents(num(t.amount)));
  }
  const invested = l.investmentOperations
    .filter((o) => o.kind === "buy" && inMonth(text(o.date)))
    .reduce((s, o) => s + num(o.cents), 0);
  const deposits = (l.contributions ?? [])
    .filter((c) => c.type === "contribution" && inMonth(text(c.date)))
    .reduce((s, c) => s + cents(num(c.amount)), 0);
  const expenseCategories = l.categories.filter((c) => text(c.type) !== "income");
  const hasBase = referenceIncome > 0;
  const lines = envelopes.map((e) => {
    const own = expenseCategories.filter((c) => c.envelope === e.id);
    let spent = own.reduce((s, c) => s + (byCategory.get(text(c.id)) ?? 0), 0);
    if (e.id === "freedom") spent += invested;
    if (e.id === "goals") spent += deposits;
    const share = shares[e.id] ?? e.defaultShare;
    const planned = hasBase ? Math.round(referenceIncome * 100 * share / 100) : null;
    const saving = e.id === "freedom" || e.id === "goals";
    return {
      type: e.id, name: e.name, share_percent: share,
      planned: planned === null ? null : money(planned),
      spent: money(spent),
      remaining: planned === null ? null : money(planned - spent),
      used_percent: planned ? Math.round((spent / planned) * 100) : null,
      over: !saving && planned !== null && planned > 0 && spent > planned,
      categories: own.map((c) => ({ id: text(c.id), name: text(c.name), spent: money(byCategory.get(text(c.id)) ?? 0) })),
      includes: e.id === "freedom" ? "compras de investimento do mês"
        : e.id === "goals" ? "depósitos em objetivos do mês" : undefined,
    };
  });
  const unassigned = expenseCategories.filter((c) => !envelopeById(c.envelope));
  const unassignedSpent = unassigned.reduce((s, c) => s + (byCategory.get(text(c.id)) ?? 0), 0);
  return {
    month,
    reference_income: hasBase ? referenceIncome : null,
    shares_total: envelopes.reduce((s, e) => s + (shares[e.id] ?? e.defaultShare), 0),
    types: lines,
    without_type: {
      spent: money(unassignedSpent),
      categories_with_spending: unassigned.filter((c) => (byCategory.get(text(c.id)) ?? 0) > 0)
        .map((c) => ({ id: text(c.id), name: text(c.name), spent: money(byCategory.get(text(c.id)) ?? 0) })),
      all_categories: unassigned.map((c) => ({ id: text(c.id), name: text(c.name) })),
    },
    total_spent: money(lines.reduce((s, x) => s + cents(x.spent), 0) + unassignedSpent),
    not_converted_other_currencies: Object.fromEntries(Object.entries(unconverted).map(([c, v]) => [c, money(v)])),
  };
}
