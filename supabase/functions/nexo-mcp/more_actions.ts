// More things the assistant can read and request: recurring items, budgets,
// categories, savings goals and card invoices. Requests are applied by the
// app with its own rules; reads come from the synced ledger.
import { cents, currencyOf, day, isNeutral, type Ledger, meta, metadataIndex, money, num, type Row, text } from "./finance.ts";
import { ToolInputError, type ToolDefinition } from "./tools.ts";

type Args = Record<string, unknown>;
type Enqueue = (kind: string, args: Record<string, unknown>) => Promise<{ id: string; status: string }>;

const dateField = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };
const amountField = { type: "number", exclusiveMinimum: 0, maximum: 1000000000, description: "Valor em reais" };
const idField = { type: "string" };

export const readOnlyMore = new Set(["get_recurring", "get_budgets", "get_goals"]);

export const moreActions: (ToolDefinition & { destructive?: boolean })[] = [
  {
    name: "get_recurring",
    title: "Recorrentes e assinaturas",
    description: "Lista contas fixas, assinaturas e parcelamentos ativos com a próxima ocorrência, para pagar, pular ou corrigir.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "pay_recurring",
    title: "Efetivar recorrente",
    description:
      "Marca a próxima ocorrência de uma recorrente como paga/recebida e cria o lançamento, como o botão Efetivar do app. " +
      "Informe amount quando o valor real foi diferente do previsto (ex.: conta de luz). Não duplica: a previsão deixa de ficar em aberto.",
    inputSchema: {
      type: "object",
      properties: {
        id: idField,
        amount: amountField,
        date: { ...dateField, description: "Data da ocorrência esperada (confirmação); padrão: a próxima" },
      },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "skip_recurring",
    title: "Pular ocorrência",
    description: "Pula a próxima ocorrência de uma recorrente sem lançar nada (parcelamentos não podem ser pulados).",
    inputSchema: {
      type: "object",
      properties: { id: idField, date: dateField },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "add_recurring",
    title: "Nova recorrente",
    description: "Cadastra conta fixa, assinatura, salário ou parcelamento que se repete.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", minLength: 1, maxLength: 80 },
        type: { type: "string", enum: ["expense", "income"] },
        amount: amountField,
        account_id: idField,
        category_id: idField,
        frequency: { type: "string", enum: ["daily", "weekly", "monthly", "yearly"], description: "Padrão monthly" },
        every: { type: "integer", minimum: 1, maximum: 12, description: "A cada N períodos; padrão 1" },
        first_date: { ...dateField, description: "Primeira cobrança" },
        end_date: { ...dateField, description: "Última cobrança (parcelamentos)" },
        kind: { type: "string", enum: ["subscription", "installment"], description: "Padrão subscription (fixa)" },
      },
      required: ["name", "type", "amount", "account_id", "category_id", "first_date"],
      additionalProperties: false,
    },
  },
  {
    name: "update_recurring",
    title: "Alterar recorrente",
    description: "Muda nome, valor, conta, categoria, próxima data ou data final de uma recorrente.",
    destructive: true,
    inputSchema: {
      type: "object",
      properties: {
        id: idField,
        name: { type: "string", minLength: 1, maxLength: 80 },
        amount: amountField,
        account_id: idField,
        category_id: idField,
        next_date: dateField,
        end_date: dateField,
      },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "delete_recurring",
    title: "Excluir recorrente",
    description: "Exclui uma recorrente e o histórico dela. Lançamentos já registrados não mudam.",
    destructive: true,
    inputSchema: { type: "object", properties: { id: idField }, required: ["id"], additionalProperties: false },
  },
  {
    name: "settle_transaction",
    title: "Marcar como pago",
    description: "Marca um lançamento pendente/previsto como pago ou recebido (o saldo passa a contar).",
    inputSchema: { type: "object", properties: { id: idField }, required: ["id"], additionalProperties: false },
  },
  {
    name: "get_budgets",
    title: "Orçamentos",
    description: "Orçamentos por categoria com quanto já foi gasto no período e quanto resta.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "set_budget",
    title: "Definir orçamento",
    description: "Cria ou altera o limite de gasto de uma categoria de despesa (mensal ou semanal).",
    inputSchema: {
      type: "object",
      properties: {
        category_id: idField,
        amount: amountField,
        period: { type: "string", enum: ["monthly", "weekly"], description: "Padrão monthly" },
      },
      required: ["category_id", "amount"],
      additionalProperties: false,
    },
  },
  {
    name: "delete_budget",
    title: "Remover orçamento",
    description: "Remove um orçamento. Nenhum lançamento muda.",
    destructive: true,
    inputSchema: { type: "object", properties: { id: idField }, required: ["id"], additionalProperties: false },
  },
  {
    name: "add_category",
    title: "Nova categoria",
    description: "Cria uma categoria de despesa ou receita.",
    inputSchema: {
      type: "object",
      properties: {
        name: { type: "string", minLength: 1, maxLength: 40 },
        type: { type: "string", enum: ["expense", "income"] },
      },
      required: ["name", "type"],
      additionalProperties: false,
    },
  },
  {
    name: "rename_category",
    title: "Renomear categoria",
    description: "Muda o nome de uma categoria.",
    inputSchema: {
      type: "object",
      properties: { id: idField, name: { type: "string", minLength: 1, maxLength: 40 } },
      required: ["id", "name"],
      additionalProperties: false,
    },
  },
  {
    name: "get_goals",
    title: "Objetivos",
    description: "Objetivos de economia (reservas) com meta, valor guardado e quanto falta.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "move_goal",
    title: "Guardar ou retirar de objetivo",
    description: "Guarda dinheiro de uma conta num objetivo, ou retira de volta para a conta. Não é gasto nem receita.",
    inputSchema: {
      type: "object",
      properties: {
        goal_id: idField,
        account_id: idField,
        amount: amountField,
        direction: { type: "string", enum: ["deposit", "withdraw"] },
        note: { type: "string", maxLength: 120 },
      },
      required: ["goal_id", "account_id", "amount", "direction"],
      additionalProperties: false,
    },
  },
  {
    name: "pay_card_invoice",
    title: "Pagar fatura",
    description:
      "Registra o pagamento da fatura de um cartão saindo de uma conta (é transferência, não gasto novo). " +
      "Padrão: a fatura fechada mais recente e o valor que falta dela.",
    inputSchema: {
      type: "object",
      properties: {
        card_id: idField,
        from_account_id: idField,
        amount: amountField,
        invoice: { type: "string", enum: ["closed", "current"], description: "Padrão closed" },
      },
      required: ["card_id", "from_account_id"],
      additionalProperties: false,
    },
  },
];

function only(args: Args, allowed: string[]) {
  const extra = Object.keys(args).filter((k) => !allowed.includes(k));
  if (extra.length) throw new ToolInputError(`Parâmetros não suportados: ${extra.join(", ")}.`);
}
function str(args: Args, key: string, max: number, required = true): string | undefined {
  const v = args[key];
  if (v === undefined && !required) return undefined;
  if (typeof v !== "string" || !v.trim() || v.length > max) throw new ToolInputError(`${key} é obrigatório (até ${max} caracteres).`);
  return v.trim();
}
function amountCents(args: Args, required = true): number | undefined {
  const v = args.amount;
  if (v === undefined && !required) return undefined;
  if (typeof v !== "number" || !isFinite(v) || v <= 0 || v > 1e9) throw new ToolInputError("amount deve ser um valor positivo em reais.");
  const c = Math.round(v * 100);
  if (Math.abs(c - v * 100) > 1e-6) throw new ToolInputError("amount aceita no máximo 2 casas decimais.");
  return c;
}
function dateArg(args: Args, key: string, required = false): string | undefined {
  const v = args[key];
  if (v === undefined) {
    if (required) throw new ToolInputError(`${key} é obrigatório (AAAA-MM-DD).`);
    return undefined;
  }
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v) || isNaN(Date.parse(`${v}T00:00:00Z`))) {
    throw new ToolInputError(`${key} deve estar no formato AAAA-MM-DD.`);
  }
  return v;
}
function enumArg<T extends string>(args: Args, key: string, values: T[], fallback: T): T {
  const v = args[key] ?? fallback;
  if (typeof v !== "string" || !values.includes(v as T)) throw new ToolInputError(`${key} deve ser: ${values.join(", ")}.`);
  return v as T;
}
const find = (rows: Row[], id: unknown) => rows.find((r) => text(r.id) === id);
function account(l: Ledger, id: string | undefined) {
  const a = find(l.accounts, id);
  if (!a) throw new ToolInputError("Conta não encontrada. Use get_accounts.");
  return a;
}
function category(l: Ledger, id: string | undefined, type?: string) {
  const c = find(l.categories, id);
  if (!c) throw new ToolInputError("Categoria não encontrada. Use get_categories.");
  if (type && text(c.type) && text(c.type) !== type) {
    throw new ToolInputError(`A categoria ${text(c.name)} é de ${text(c.type) === "income" ? "receita" : "despesa"}.`);
  }
  return c;
}
function recurring(l: Ledger, id: string | undefined) {
  const r = find(l.recurring, id);
  if (!r) throw new ToolInputError("Recorrente não encontrada. Use get_recurring.");
  return r;
}
const pending = (id: string, what: string) => ({
  request_id: id,
  status: "pendente",
  message: `${what} enviado ao Nexo. Ele é gravado quando o app estiver aberto no celular ou no PC; confira com get_request_status.`,
});
const unit: Record<string, string> = { daily: "days", weekly: "weeks", monthly: "months", yearly: "years" };
const unitLabel: Record<string, string> = { days: "dia(s)", weeks: "semana(s)", months: "mês(es)", years: "ano(s)" };

function nextOf(r: Row): string {
  return day(text(r.next_date));
}

function budgetSpentCents(l: Ledger, b: Row, today: string): number {
  const [y, m, d] = today.split("-").map(Number);
  let from: string, to: string;
  if (text(b.period) === "weekly") {
    // The app's week start is a per-device setting; Sunday is its default.
    const now = new Date(Date.UTC(y, m - 1, d));
    const start = new Date(now);
    start.setUTCDate(now.getUTCDate() - now.getUTCDay());
    const end = new Date(start);
    end.setUTCDate(start.getUTCDate() + 7);
    from = start.toISOString().slice(0, 10);
    to = end.toISOString().slice(0, 10);
  } else {
    from = `${y}-${String(m).padStart(2, "0")}-01`;
    const next = new Date(Date.UTC(y, m, 1));
    to = next.toISOString().slice(0, 10);
  }
  const metas = metadataIndex(l);
  let total = 0;
  for (const tx of l.transactions) {
    if (tx.type !== "expense" || text(tx.category_id) !== text(b.category_id)) continue;
    const date = day(text(tx.date));
    if (date < from || date >= to) continue;
    if (isNeutral(tx, meta(metas.get(text(tx.id))))) continue;
    if (currencyOf(l, tx) !== l.mainCurrency) continue;
    total += cents(num(tx.amount));
  }
  return total;
}

export async function callMoreAction(name: string, rawArgs: unknown, l: Ledger, today: string,
  enqueue: Enqueue): Promise<Record<string, unknown> | null> {
  const args = (rawArgs ?? {}) as Args;
  if (typeof args !== "object" || Array.isArray(args)) throw new ToolInputError("Argumentos inválidos.");
  switch (name) {
    case "get_recurring": {
      only(args, []);
      return {
        recurring: (l.recurring ?? [])
          .filter((r) => !r.end_date || nextOf(r) <= day(text(r.end_date)))
          .map((r) => ({
            id: text(r.id),
            name: text(r.name),
            type: text(r.payment_type) || "expense",
            amount: money(cents(num(r.amount))),
            next_date: nextOf(r),
            overdue: nextOf(r) < today,
            every: `${num(r.freq_val) || 1} ${unitLabel[text(r.freq_unit)] ?? text(r.freq_unit)}`,
            kind: text(r.recurring_type) === "installment" ? "parcelamento" : "fixa/assinatura",
            account: text(find(l.accounts, r.account_id)?.name),
            account_id: text(r.account_id),
            category: text(find(l.categories, r.category_id)?.name),
            category_id: text(r.category_id),
            end_date: r.end_date ? day(text(r.end_date)) : undefined,
          }))
          .sort((a, b) => a.next_date.localeCompare(b.next_date)),
        note: "Ocorrências futuras são previsões: só viram lançamento ao efetivar (pay_recurring).",
      };
    }
    case "pay_recurring":
    case "skip_recurring": {
      only(args, name === "pay_recurring" ? ["id", "amount", "date"] : ["id", "date"]);
      const r = recurring(l, str(args, "id", 256));
      const expected = dateArg(args, "date");
      if (expected && expected !== nextOf(r)) {
        throw new ToolInputError(`A próxima ocorrência de ${text(r.name)} é em ${nextOf(r)}.`);
      }
      if (name === "skip_recurring" && text(r.recurring_type) === "installment") {
        throw new ToolInputError("Parcelamentos não podem ser pulados: a parcela continua devida.");
      }
      const body: Args = { id: text(r.id), expected_date: nextOf(r) };
      if (name === "pay_recurring") {
        const c = amountCents(args, false);
        if (c !== undefined) body.amount_cents = c;
      }
      const q = await enqueue(name === "pay_recurring" ? "recurring.pay" : "recurring.skip", body);
      return pending(q.id, name === "pay_recurring" ? "Efetivação" : "Pulo da ocorrência");
    }
    case "add_recurring": {
      only(args, ["name", "type", "amount", "account_id", "category_id", "frequency", "every", "first_date", "end_date", "kind"]);
      const type = enumArg(args, "type", ["expense", "income"], "expense");
      const a = account(l, str(args, "account_id", 256));
      category(l, str(args, "category_id", 256), type);
      const every = args.every ?? 1;
      if (typeof every !== "number" || !Number.isInteger(every) || every < 1 || every > 12) {
        throw new ToolInputError("every deve ser um inteiro entre 1 e 12.");
      }
      const first = dateArg(args, "first_date", true)!;
      const end = dateArg(args, "end_date");
      if (end && end < first) throw new ToolInputError("end_date deve ser depois de first_date.");
      const kind = enumArg(args, "kind", ["subscription", "installment"], "subscription");
      if (kind === "installment" && !end) throw new ToolInputError("Parcelamento precisa de end_date.");
      const q = await enqueue("recurring.add", {
        name: str(args, "name", 80), type, amount_cents: amountCents(args), account_id: text(a.id),
        category_id: args.category_id, freq_unit: unit[enumArg(args, "frequency", ["daily", "weekly", "monthly", "yearly"], "monthly")],
        freq_val: every, first_date: first, end_date: end ?? null, kind,
      });
      return pending(q.id, "Nova recorrente");
    }
    case "update_recurring": {
      only(args, ["id", "name", "amount", "account_id", "category_id", "next_date", "end_date"]);
      const r = recurring(l, str(args, "id", 256));
      const change: Args = { id: text(r.id) };
      const nm = str(args, "name", 80, false);
      if (nm) change.name = nm;
      const c = amountCents(args, false);
      if (c !== undefined) change.amount_cents = c;
      if (args.account_id !== undefined) change.account_id = text(account(l, str(args, "account_id", 256)).id);
      if (args.category_id !== undefined) {
        category(l, str(args, "category_id", 256), text(r.payment_type) || "expense");
        change.category_id = args.category_id;
      }
      const nd = dateArg(args, "next_date");
      if (nd) change.next_date = nd;
      const ed = dateArg(args, "end_date");
      if (ed) change.end_date = ed;
      if (Object.keys(change).length === 1) throw new ToolInputError("Informe o que deve mudar.");
      const q = await enqueue("recurring.update", change);
      return pending(q.id, "Alteração da recorrente");
    }
    case "delete_recurring": {
      only(args, ["id"]);
      const r = recurring(l, str(args, "id", 256));
      return pending((await enqueue("recurring.delete", { id: text(r.id) })).id, "Exclusão da recorrente");
    }
    case "settle_transaction": {
      only(args, ["id"]);
      const id = str(args, "id", 256)!;
      const tx = find(l.transactions, id);
      if (!tx) throw new ToolInputError("Lançamento não encontrado.");
      if (meta(metadataIndex(l).get(id)).status !== "pending") {
        throw new ToolInputError("Este lançamento já está pago/recebido.");
      }
      return pending((await enqueue("transaction.settle", { id })).id, "Baixa do lançamento");
    }
    case "get_budgets": {
      only(args, []);
      return {
        budgets: (l.budgets ?? []).map((b) => {
          const spent = budgetSpentCents(l, b, today);
          const limit = cents(num(b.amount));
          return {
            id: text(b.id),
            category: text(find(l.categories, b.category_id)?.name) || "Categoria",
            category_id: text(b.category_id),
            period: text(b.period) === "weekly" ? "semanal" : "mensal",
            limit: money(limit),
            spent: money(spent),
            remaining: money(limit - spent),
            used_percent: limit > 0 ? Math.round((spent / limit) * 100) : null,
          };
        }),
        note: "Inclui gastos pendentes do período, como no app. Semana começando no domingo.",
      };
    }
    case "set_budget": {
      only(args, ["category_id", "amount", "period"]);
      const c = category(l, str(args, "category_id", 256), "expense");
      const q = await enqueue("budget.set", {
        category_id: text(c.id), amount_cents: amountCents(args),
        period: enumArg(args, "period", ["monthly", "weekly"], "monthly"),
      });
      return pending(q.id, "Orçamento");
    }
    case "delete_budget": {
      only(args, ["id"]);
      const id = str(args, "id", 256)!;
      if (!find(l.budgets ?? [], id)) throw new ToolInputError("Orçamento não encontrado. Use get_budgets.");
      return pending((await enqueue("budget.delete", { id })).id, "Remoção do orçamento");
    }
    case "add_category": {
      only(args, ["name", "type"]);
      const nm = str(args, "name", 40)!;
      const type = enumArg(args, "type", ["expense", "income"], "expense");
      if (l.categories.some((c) => text(c.name).toLowerCase() === nm.toLowerCase() && text(c.type) === type)) {
        throw new ToolInputError("Já existe uma categoria com esse nome.");
      }
      return pending((await enqueue("category.add", { name: nm, type })).id, "Nova categoria");
    }
    case "rename_category": {
      only(args, ["id", "name"]);
      const c = category(l, str(args, "id", 256));
      return pending((await enqueue("category.update", { id: text(c.id), name: str(args, "name", 40) })).id, "Renomeação");
    }
    case "get_goals": {
      only(args, []);
      return {
        goals: (l.goals ?? []).map((g) => {
          const target = cents(num(g.target_amount)), saved = cents(num(g.current_amount));
          return {
            id: text(g.id),
            name: text(g.name),
            target: money(target),
            saved: money(saved),
            missing: money(Math.max(target - saved, 0)),
            target_date: g.target_date ? day(text(g.target_date)) : undefined,
            completed: g.is_completed === 1 || g.is_completed === true,
          };
        }),
      };
    }
    case "move_goal": {
      only(args, ["goal_id", "account_id", "amount", "direction", "note"]);
      const g = find(l.goals ?? [], args.goal_id);
      if (!g) throw new ToolInputError("Objetivo não encontrado. Use get_goals.");
      const a = account(l, str(args, "account_id", 256));
      if (text(a.type) === "credit") throw new ToolInputError("Use uma conta, não um cartão de crédito.");
      const q = await enqueue("goal.move", {
        goal_id: text(g.id), account_id: text(a.id), amount_cents: amountCents(args),
        direction: enumArg(args, "direction", ["deposit", "withdraw"], "deposit"),
        note: str(args, "note", 120, false) ?? "",
      });
      return pending(q.id, "Movimentação do objetivo");
    }
    case "pay_card_invoice": {
      only(args, ["card_id", "from_account_id", "amount", "invoice"]);
      const card = account(l, str(args, "card_id", 256));
      if (text(card.type) !== "credit") throw new ToolInputError("card_id deve ser um cartão de crédito.");
      const from = account(l, str(args, "from_account_id", 256));
      if (text(from.type) === "credit") throw new ToolInputError("Pague a partir de uma conta, não de outro cartão.");
      const body: Args = {
        card_id: text(card.id), from_account_id: text(from.id),
        invoice: enumArg(args, "invoice", ["closed", "current"], "closed"),
      };
      const c = amountCents(args, false);
      if (c !== undefined) body.amount_cents = c;
      return pending((await enqueue("invoice.pay", body)).id, "Pagamento da fatura");
    }
    default:
      return null;
  }
}
