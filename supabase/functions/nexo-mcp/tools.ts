// Read-only Nexo tools. Every number comes from the synchronized ledger; when
// something is unknown (another currency, no data) the answer says so.
import {
  analyze, cents, currencyOf, day, isNeutral, isoDay, type Ledger, meta, metadataIndex,
  money, monthFilter, num, previousMonth, type Row, text,
} from "./finance.ts";

export class ToolInputError extends Error {}

export interface ToolDefinition {
  name: string;
  title: string;
  description: string;
  inputSchema: Record<string, unknown>;
}

const dateField = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };

export const tools: ToolDefinition[] = [
  {
    name: "get_financial_summary",
    title: "Resumo financeiro do mês",
    description:
      "Saldo das contas, dívida de cartões, receitas, consumo, estornos, resultado e despesas pendentes de um mês, com comparação ao mês anterior no mesmo período. Transferências, reservas e pagamentos de fatura não contam como consumo.",
    inputSchema: {
      type: "object",
      properties: { month: { type: "string", pattern: "^\\d{4}-\\d{2}$", description: "AAAA-MM; padrão: mês atual" } },
      additionalProperties: false,
    },
  },
  {
    name: "get_accounts",
    title: "Contas e cartões",
    description: "Lista contas, cartões e saldos atuais.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "list_transactions",
    title: "Lançamentos",
    description:
      "Lista lançamentos com filtros. Datas AAAA-MM-DD inclusivas. Cada item informa se conta como consumo e se está pendente.",
    inputSchema: {
      type: "object",
      properties: {
        from: dateField,
        to: dateField,
        account_id: { type: "string" },
        category_id: { type: "string" },
        type: { type: "string", enum: ["income", "expense"] },
        search: { type: "string", maxLength: 80, description: "Trecho da descrição ou observação" },
        limit: { type: "integer", minimum: 1, maximum: 100 },
      },
      additionalProperties: false,
    },
  },
  {
    name: "get_transaction",
    title: "Detalhe de um lançamento",
    description: "Mostra um lançamento pelo identificador.",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string", maxLength: 256 } },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "get_spending_by_category",
    title: "Gastos por categoria",
    description:
      "Consumo por categoria num período, opcionalmente comparado ao período anterior de mesma duração.",
    inputSchema: {
      type: "object",
      properties: { from: dateField, to: dateField, compare_previous: { type: "boolean" } },
      required: ["from", "to"],
      additionalProperties: false,
    },
  },
  {
    name: "get_upcoming_bills",
    title: "Contas a vencer",
    description:
      "Despesas pendentes que vencem nos próximos dias (e as atrasadas) e recorrentes previstas. Previsões não são pagamentos.",
    inputSchema: {
      type: "object",
      properties: { days: { type: "integer", minimum: 1, maximum: 90 } },
      additionalProperties: false,
    },
  },
  {
    name: "get_investment_summary",
    title: "Carteira de investimentos",
    description:
      "Posições com quantidade, última cotação registrada e valor de referência. Cotação não é saldo nem rentabilidade pessoal.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
];

type Args = Record<string, unknown>;

function only(args: Args, allowed: string[]) {
  for (const key of Object.keys(args)) {
    if (!allowed.includes(key)) throw new ToolInputError(`Campo desconhecido: ${key}`);
  }
}
function date(args: Args, key: string, fallback?: string): string {
  const v = args[key] ?? fallback;
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v) || isNaN(Date.parse(v))) {
    throw new ToolInputError(`Data inválida em ${key}; use AAAA-MM-DD.`);
  }
  return v;
}
function optionalString(args: Args, key: string, max = 256): string | undefined {
  const v = args[key];
  if (v === undefined) return undefined;
  if (typeof v !== "string" || v.length === 0 || v.length > max) throw new ToolInputError(`Valor inválido em ${key}.`);
  return v;
}
function integer(args: Args, key: string, min: number, max: number, fallback: number): number {
  const v = args[key] ?? fallback;
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max) {
    throw new ToolInputError(`${key} deve ser um inteiro entre ${min} e ${max}.`);
  }
  return v;
}

const categoryName = (l: Ledger, id: string) =>
  text(l.categories.find((c) => c.id === id)?.name) || "Sem categoria";
const accountName = (l: Ledger, id: string) =>
  text(l.accounts.find((a) => a.id === id)?.name) || "Conta removida";

function balanceCents(l: Ledger, id: string): number {
  return Math.round((l.balances[id] ?? 0) / 10000);
}

function describeTx(l: Ledger, tx: Row, metas: Map<string, Row>) {
  const m = meta(metas.get(text(tx.id)));
  return {
    id: text(tx.id),
    date: day(text(tx.date)),
    type: tx.type,
    amount: money(cents(num(tx.amount))),
    currency: currencyOf(l, tx),
    description: text(tx.description),
    account: accountName(l, text(tx.account_id)),
    account_id: text(tx.account_id),
    category: categoryName(l, text(tx.category_id)),
    category_id: text(tx.category_id),
    subcategory: m.subcategory || undefined,
    status: m.status === "pending" ? "pendente" : "realizado",
    due_date: m.dueDate ? day(m.dueDate) : undefined,
    counts_as_spending: tx.type === "expense" && m.status !== "pending" && !isNeutral(tx, m),
    installment: m.installmentCurrent && m.installmentTotal ? `${m.installmentCurrent}/${m.installmentTotal}` : undefined,
    note: text(tx.note) || undefined,
  };
}

function shift(dayIso: string, days: number): string {
  const d = new Date(`${dayIso}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return isoDay(d);
}

export function callTool(name: string, rawArgs: unknown, l: Ledger, today: string): Record<string, unknown> {
  const args = (rawArgs ?? {}) as Args;
  if (typeof args !== "object" || Array.isArray(args)) throw new ToolInputError("Argumentos inválidos.");
  const metas = metadataIndex(l);
  switch (name) {
    case "get_financial_summary": {
      only(args, ["month"]);
      const month = args.month ?? today.slice(0, 7);
      if (typeof month !== "string" || !/^\d{4}-(0[1-9]|1[0-2])$/.test(month)) {
        throw new ToolInputError("month deve ser AAAA-MM.");
      }
      const current = monthFilter(month, today);
      const partial = today.slice(0, 7) === month;
      const now = analyze(l, current);
      const before = analyze(l, previousMonth(current, partial));
      let cash = 0, cards = 0;
      for (const a of l.accounts) {
        if (text(a.currency) !== l.mainCurrency || a.type === "gold") continue;
        const b = balanceCents(l, text(a.id));
        if (a.type === "credit") cards += b;
        else if (a.exclude_from_total !== 1) cash += b;
      }
      return {
        currency: l.mainCurrency,
        period: current,
        accounts_balance: money(cash),
        cards_balance: money(cards),
        income: money(now.income),
        spending: money(now.expense),
        refunds: money(now.refunds),
        result: money(now.result),
        pending_expenses: money(now.pendingExpense),
        transfers_and_reserves_excluded: money(now.transfers),
        top_categories: Object.entries(now.categories).sort((a, b) => b[1] - a[1]).slice(0, 5)
          .map(([id, v]) => ({ category: categoryName(l, id), amount: money(v) })),
        previous_period: previousMonth(current, partial),
        previous_spending: money(before.expense),
        spending_change_percent: before.expense === 0 ? null
          : Math.round(((now.expense - before.expense) / before.expense) * 1000) / 10,
        not_converted_other_currencies: Object.fromEntries(
          Object.entries(now.unconverted).map(([c, v]) => [c, money(v)]),
        ),
      };
    }
    case "get_accounts": {
      only(args, []);
      return {
        accounts: l.accounts.map((a) => ({
          id: text(a.id),
          name: text(a.name),
          type: text(a.type),
          currency: text(a.currency),
          balance: money(balanceCents(l, text(a.id))),
          excluded_from_total: a.exclude_from_total === 1,
        })),
      };
    }
    case "list_transactions": {
      only(args, ["from", "to", "account_id", "category_id", "type", "search", "limit"]);
      const to = date(args, "to", today);
      const from = date(args, "from", shift(to, -30));
      if (from > to) throw new ToolInputError("from deve ser anterior a to.");
      const type = optionalString(args, "type");
      if (type !== undefined && type !== "income" && type !== "expense") throw new ToolInputError("type inválido.");
      const account = optionalString(args, "account_id");
      const category = optionalString(args, "category_id");
      const search = optionalString(args, "search", 80)?.toLowerCase();
      const limit = integer(args, "limit", 1, 100, 50);
      const rows = l.transactions
        .filter((t) => {
          const d = day(text(t.date));
          return d >= from && d <= to &&
            (account === undefined || t.account_id === account) &&
            (category === undefined || t.category_id === category) &&
            (type === undefined || t.type === type) &&
            (search === undefined ||
              `${text(t.description)} ${text(t.note)}`.toLowerCase().includes(search));
        })
        .sort((a, b) => text(b.date).localeCompare(text(a.date)));
      return {
        from, to,
        total_found: rows.length,
        truncated: rows.length > limit,
        transactions: rows.slice(0, limit).map((t) => describeTx(l, t, metas)),
      };
    }
    case "get_transaction": {
      only(args, ["id"]);
      const id = optionalString(args, "id");
      const tx = l.transactions.find((t) => t.id === id);
      if (!tx) throw new ToolInputError("Lançamento não encontrado.");
      return { transaction: describeTx(l, tx, metas) };
    }
    case "get_spending_by_category": {
      only(args, ["from", "to", "compare_previous"]);
      const from = date(args, "from"), to = date(args, "to");
      if (from > to) throw new ToolInputError("from deve ser anterior a to.");
      const now = analyze(l, { from, to });
      const result: Record<string, unknown> = {
        currency: l.mainCurrency, from, to, total: money(now.expense),
        categories: Object.entries(now.categories).sort((a, b) => b[1] - a[1])
          .map(([id, v]) => ({ category: categoryName(l, id), category_id: id, amount: money(v) })),
        not_converted_other_currencies: Object.fromEntries(
          Object.entries(now.unconverted).map(([c, v]) => [c, money(v)]),
        ),
      };
      if (args.compare_previous === true) {
        const length = Math.round((Date.parse(to) - Date.parse(from)) / 86400000) + 1;
        const pTo = shift(from, -1), pFrom = shift(pTo, -(length - 1));
        const before = analyze(l, { from: pFrom, to: pTo });
        result.previous = {
          from: pFrom, to: pTo, total: money(before.expense),
          categories: Object.entries(before.categories).sort((a, b) => b[1] - a[1])
            .map(([id, v]) => ({ category: categoryName(l, id), category_id: id, amount: money(v) })),
        };
      } else if (args.compare_previous !== undefined && typeof args.compare_previous !== "boolean") {
        throw new ToolInputError("compare_previous deve ser verdadeiro ou falso.");
      }
      return result;
    }
    case "get_upcoming_bills": {
      only(args, ["days"]);
      const days = integer(args, "days", 1, 90, 30);
      const until = shift(today, days);
      const pending = l.transactions
        .map((t) => ({ t, m: meta(metas.get(text(t.id))) }))
        .filter(({ t, m }) => t.type === "expense" && m.status === "pending")
        .map(({ t, m }) => ({ ...describeTx(l, t, metas), due: day(m.dueDate ?? text(t.date)) }))
        .filter((b) => b.due <= until)
        .sort((a, b) => a.due.localeCompare(b.due))
        .map((b) => ({ ...b, overdue: b.due < today }));
      const recurring = l.recurring
        .filter((r) => r.payment_type !== "income")
        .map((r) => ({ r, next: day(text(r.next_date)) }))
        .filter(({ r, next }) =>
          next <= until && (typeof r.end_date !== "string" || next <= day(r.end_date)))
        .sort((a, b) => a.next.localeCompare(b.next))
        .map(({ r, next }) => ({
          name: text(r.name), amount: money(cents(num(r.amount))), next_date: next,
          account: accountName(l, text(r.account_id)), overdue: next < today, kind: "previsto",
        }));
      return { from: today, until, pending_expenses: pending, recurring_expected: recurring };
    }
    case "get_investment_summary": {
      only(args, []);
      const positions = l.investments
        .filter((i) => i.archived !== 1)
        .map((i) => {
          const ops = l.investmentOperations.filter((o) => o.investment_id === i.id);
          const quantity = ops.reduce((q, o) => q + (o.kind === "sell" ? -num(o.quantity) : o.kind === "income" ? 0 : num(o.quantity)), 0);
          const units = quantity / 1e6;
          const price = num(i.price_micros) / 1e6;
          return {
            name: text(i.name), ticker: text(i.ticker) || undefined, asset_class: text(i.asset_class),
            quantity: units, last_price: price, price_date: day(text(i.price_at)),
            price_source: text(i.price_source), reference_value: Math.round(units * price * 100) / 100,
          };
        })
        .filter((p) => p.quantity > 0);
      return {
        currency: "BRL",
        positions,
        reference_total: Math.round(positions.reduce((s, p) => s + p.reference_value, 0) * 100) / 100,
        note: "Valor de referência pela última cotação registrada; não é saldo de conta nem rentabilidade.",
      };
    }
    default:
      throw new ToolInputError(`Ferramenta desconhecida: ${name}`);
  }
}
