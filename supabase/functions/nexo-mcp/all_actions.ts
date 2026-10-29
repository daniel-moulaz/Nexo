// The rest of the app for the assistant: accounts and balance adjustments,
// categories, goals, investments, loans, money lent, assets and the
// wishlist. Reads come from the synced ledger; changes are requests the app
// applies with its own rules (the same calls as its screens).
import { cents, day, type Ledger, money, num, type Row, text } from "./finance.ts";
import { balanceCents, ToolInputError, type ToolDefinition } from "./tools.ts";
import { cardInvoices } from "./invoices.ts";

type Args = Record<string, unknown>;
type Enqueue = (kind: string, args: Record<string, unknown>) => Promise<{ id: string; status: string }>;

const dateField = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };
const amountField = { type: "number", exclusiveMinimum: 0, maximum: 1000000000, description: "Valor em reais" };
const idField = { type: "string" };
const obj = (properties: Record<string, unknown>, required: string[] = []) => ({
  type: "object", properties, required, additionalProperties: false,
});
const accountTypes = ["bank", "cash", "savings", "wallet", "credit", "debit"];

export const readOnlyAll = new Set(["get_card_invoices", "get_investments", "get_loans", "get_lended", "get_assets", "get_wishlist"]);

export const allActions: (ToolDefinition & { destructive?: boolean })[] = [
  {
    name: "get_card_invoices", title: "Faturas dos cartões",
    description:
      "Faturas de cada cartão: período de compras, fechamento, vencimento, total, pago, restante e situação " +
      "(aberta, fechada, paga, atrasada) e quanto do limite está usado. include_transactions: o extrato de cada fatura " +
      "(compras, estornos e pagamentos com id; apagar o pagamento com delete_transaction reabre a fatura).",
    inputSchema: obj({ card_id: idField, include_transactions: { type: "boolean" } }),
  },
  {
    name: "add_account", title: "Nova conta ou cartão",
    description: "Cria conta (banco, dinheiro, poupança, carteira, débito) ou cartão de crédito com saldo inicial. Cartão: saldo negativo é fatura em aberto.",
    inputSchema: obj({
      name: { type: "string", minLength: 1, maxLength: 60 }, type: { type: "string", enum: accountTypes },
      balance: { type: "number", minimum: -1000000000, maximum: 1000000000, description: "Saldo inicial em reais (padrão 0)" },
      statement_day: { type: "integer", minimum: 1, maximum: 31 }, due_day: { type: "integer", minimum: 1, maximum: 31 },
      credit_limit: amountField,
    }, ["name", "type"]),
  },
  {
    name: "update_account", title: "Alterar conta",
    description:
      "Muda nome, cor, se entra no saldo total ou no total dos bancos e, no cartão, fechamento, vencimento, limite, conta de " +
      "pagamento, pagamento mínimo e lembrete (null tira o valor). Para o saldo use adjust_account_balance.",
    inputSchema: obj({
      id: idField, name: { type: "string", minLength: 1, maxLength: 60 },
      statement_day: { type: ["integer", "null"], minimum: 1, maximum: 31 }, due_day: { type: ["integer", "null"], minimum: 1, maximum: 31 },
      credit_limit: { type: ["number", "null"], exclusiveMinimum: 0, maximum: 1000000000 }, exclude_from_total: { type: "boolean" },
      exclude_from_bank_total: { type: "boolean" }, payment_account_id: { type: ["string", "null"], description: "Conta de onde a fatura costuma ser paga" },
      min_payment: { type: ["number", "null"], minimum: 0 }, min_payment_percent: { type: ["number", "null"], minimum: 0, maximum: 100 },
      color: { type: "string", pattern: "^#[0-9A-Fa-f]{6}$" }, reminder_enabled: { type: "boolean" },
      reminder_time: { type: "string", pattern: "^\\d{2}:\\d{2}$" },
    }, ["id"]),
  },
  {
    name: "adjust_account_balance", title: "Ajustar saldo",
    description:
      "Corrige o saldo de uma conta para o valor real, como editar o saldo no app: NÃO conta como gasto nem receita. " +
      "Use isto (e não uma despesa/receita) para acertar diferenças com o extrato do banco.",
    inputSchema: obj({ account_id: idField, balance: { type: "number", minimum: -1000000000, maximum: 1000000000, description: "Saldo correto em reais" } },
      ["account_id", "balance"]),
  },
  {
    name: "delete_account", title: "Excluir conta", destructive: true,
    description: "Exclui uma conta sem nenhum lançamento, recorrente ou vínculo (o app recusa se houver).",
    inputSchema: obj({ id: idField }, ["id"]),
  },
  {
    name: "delete_category", title: "Excluir categoria", destructive: true,
    description: "Exclui uma categoria sem lançamentos, recorrentes ou orçamentos.",
    inputSchema: obj({ id: idField }, ["id"]),
  },
  {
    name: "add_goal", title: "Novo objetivo",
    description: "Cria um objetivo de economia (reserva) com meta e prazo opcional.",
    inputSchema: obj({ name: { type: "string", minLength: 1, maxLength: 60 }, target: amountField, target_date: dateField }, ["name", "target"]),
  },
  {
    name: "update_goal", title: "Alterar objetivo",
    description: "Muda nome, meta, prazo (null tira), cor ou marca como concluído/reaberto.",
    inputSchema: obj({
      id: idField, name: { type: "string", minLength: 1, maxLength: 60 }, target: amountField,
      target_date: { type: ["string", "null"] }, completed: { type: "boolean" },
      color: { type: "string", pattern: "^#[0-9A-Fa-f]{6}$" },
    }, ["id"]),
  },
  {
    name: "delete_goal", title: "Excluir objetivo", destructive: true,
    description: "Exclui um objetivo vazio (retire o dinheiro guardado com move_goal antes).",
    inputSchema: obj({ id: idField }, ["id"]),
  },
  {
    name: "get_investments", title: "Ativos da carteira",
    description: "Lista os investimentos com id, quantidade e último preço, para registrar operações ou atualizar preço.",
    inputSchema: obj({}),
  },
  {
    name: "add_investment", title: "Novo investimento",
    description:
      "Cadastra um ativo. Com cash_account_id é uma compra que sai da conta (não é gasto); sem conta é uma posição que você já tinha.",
    inputSchema: obj({
      name: { type: "string", minLength: 1, maxLength: 80 },
      asset_class: { type: "string", enum: ["Ações", "FIIs", "ETFs", "Renda fixa", "Cripto", "Outros"] },
      ticker: { type: "string", maxLength: 12 }, institution: { type: "string", maxLength: 60 },
      quantity: { type: "number", exclusiveMinimum: 0, maximum: 1000000 }, total: amountField, date: dateField,
      cash_account_id: idField,
    }, ["name", "asset_class", "quantity", "total", "date"]),
  },
  {
    name: "record_investment_operation", title: "Compra, venda ou provento",
    description: "Registra compra/aporte, venda/resgate ou provento de um ativo. Com cash_account_id movimenta a conta (não é gasto; provento entra como receita).",
    inputSchema: obj({
      investment_id: idField, kind: { type: "string", enum: ["buy", "sell", "income"] },
      quantity: { type: "number", exclusiveMinimum: 0, maximum: 1000000, description: "Obrigatório em compra e venda" },
      total: amountField, date: dateField, cash_account_id: idField,
    }, ["investment_id", "kind", "total", "date"]),
  },
  {
    name: "update_investment_price", title: "Atualizar preço",
    description: "Informa o preço atual por unidade de um ativo (renda fixa, cripto e outros sem cotação automática).",
    inputSchema: obj({ investment_id: idField, price: amountField, date: dateField }, ["investment_id", "price"]),
  },
  {
    name: "get_loans", title: "Empréstimos e financiamentos",
    description: "Lista empréstimos/financiamentos com parcela, quanto já foi pago e se está quitado.",
    inputSchema: obj({}),
  },
  {
    name: "pay_loan_installment", title: "Pagar parcela",
    description: "Registra o pagamento de uma parcela (padrão: valor da parcela, saindo da conta do empréstimo).",
    inputSchema: obj({ id: idField, amount: amountField, account_id: idField }, ["id"]),
  },
  {
    name: "skip_loan_installment", title: "Pular parcela",
    description: "Marca a parcela do mês como pulada, sem movimentar conta.",
    inputSchema: obj({ id: idField }, ["id"]),
  },
  {
    name: "get_lended", title: "Emprestado e devido",
    description: "Dinheiro que você emprestou ou pegou emprestado com pessoas, em aberto e quitado.",
    inputSchema: obj({}),
  },
  {
    name: "add_lended", title: "Emprestei / peguei emprestado",
    description: "Registra dinheiro emprestado a alguém (lent) ou que você pegou (borrowed). Com account_id movimenta a conta; não é gasto nem receita.",
    inputSchema: obj({
      person: { type: "string", minLength: 1, maxLength: 60 }, type: { type: "string", enum: ["lent", "borrowed"] },
      amount: amountField, account_id: idField, date: dateField, due_date: dateField, notes: { type: "string", maxLength: 200 },
    }, ["person", "type", "amount", "date"]),
  },
  {
    name: "settle_lended", title: "Quitar empréstimo pessoal",
    description: "Marca como devolvido/pago; a conta vinculada volta a ser movimentada no sentido contrário.",
    inputSchema: obj({ id: idField }, ["id"]),
  },
  {
    name: "get_assets", title: "Bens", description: "Bens cadastrados (carro, imóvel...) com valor estimado.",
    inputSchema: obj({}),
  },
  {
    name: "add_asset", title: "Novo bem", description: "Cadastra um bem com valor estimado (entra no patrimônio, não nas contas).",
    inputSchema: obj({ name: { type: "string", minLength: 1, maxLength: 60 }, value: amountField, notes: { type: "string", maxLength: 200 } }, ["name", "value"]),
  },
  {
    name: "update_asset", title: "Alterar bem", description: "Muda nome ou valor estimado de um bem.",
    inputSchema: obj({ id: idField, name: { type: "string", minLength: 1, maxLength: 60 }, value: amountField }, ["id"]),
  },
  {
    name: "delete_asset", title: "Excluir bem", destructive: true, description: "Remove um bem do patrimônio.",
    inputSchema: obj({ id: idField }, ["id"]),
  },
  {
    name: "get_wishlist", title: "Lista de desejos", description: "Itens que você quer comprar, com preço e prioridade.",
    inputSchema: obj({}),
  },
  {
    name: "add_wishlist_item", title: "Novo desejo", description: "Adiciona um item à lista de desejos.",
    inputSchema: obj({
      name: { type: "string", minLength: 1, maxLength: 80 }, price: amountField,
      priority: { type: "string", enum: ["low", "medium", "high"] }, notes: { type: "string", maxLength: 200 },
    }, ["name", "price"]),
  },
  {
    name: "update_wishlist_item", title: "Alterar desejo", description: "Muda nome, preço, prioridade ou marca como comprado.",
    inputSchema: obj({
      id: idField, name: { type: "string", minLength: 1, maxLength: 80 }, price: amountField,
      priority: { type: "string", enum: ["low", "medium", "high"] }, purchased: { type: "boolean" },
    }, ["id"]),
  },
  {
    name: "delete_wishlist_item", title: "Remover desejo", destructive: true, description: "Remove um item da lista de desejos.",
    inputSchema: obj({ id: idField }, ["id"]),
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
function reais(args: Args, key: string, opts: { required?: boolean; signed?: boolean } = {}): number | undefined {
  const v = args[key];
  if (v === undefined && opts.required === false) return undefined;
  if (typeof v !== "number" || !isFinite(v) || Math.abs(v) > 1e9 || (!opts.signed && v <= 0)) {
    throw new ToolInputError(`${key} deve ser um valor${opts.signed ? "" : " positivo"} em reais.`);
  }
  const c = Math.round(v * 100);
  if (Math.abs(c - v * 100) > 1e-6) throw new ToolInputError(`${key} aceita no máximo 2 casas decimais.`);
  return c;
}
function quantityMicros(args: Args, required: boolean): number | undefined {
  const v = args.quantity;
  if (v === undefined && !required) return undefined;
  if (typeof v !== "number" || !isFinite(v) || v <= 0 || v > 1e6) throw new ToolInputError("quantity deve ser positiva.");
  const micros = Math.round(v * 1e6);
  if (Math.abs(micros - v * 1e6) > 1e-3) throw new ToolInputError("quantity aceita no máximo 6 casas decimais.");
  return micros;
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
function dayOfMonth(args: Args, key: string): number | undefined {
  const v = args[key];
  if (v === undefined) return undefined;
  if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 31) throw new ToolInputError(`${key} deve ser um dia entre 1 e 31.`);
  return v;
}
function oneOf<T extends string>(args: Args, key: string, values: T[], fallback?: T): T {
  const v = args[key] ?? fallback;
  if (typeof v !== "string" || !values.includes(v as T)) throw new ToolInputError(`${key} deve ser: ${values.join(", ")}.`);
  return v as T;
}
const find = (rows: Row[] | undefined, id: unknown) => (rows ?? []).find((r) => text(r.id) === id);
function account(l: Ledger, id: string | undefined, noCredit = false) {
  const a = find(l.accounts, id);
  if (!a) throw new ToolInputError("Conta não encontrada. Use get_accounts.");
  if (noCredit && text(a.type) === "credit") throw new ToolInputError("Use uma conta, não um cartão de crédito.");
  return a;
}
const pending = (id: string, what: string) => ({
  request_id: id,
  status: "pendente",
  message: `${what} enviado ao Nexo. Ele é gravado quando o app estiver aberto no celular ou no PC; confira com get_request_status.`,
});
function changes(args: Args, base: Args, fields: [string, (a: Args) => unknown][]): Args {
  const out: Args = { ...base };
  for (const [key, read] of fields) {
    const v = read(args);
    if (v !== undefined) out[key] = v;
  }
  if (Object.keys(out).length === Object.keys(base).length) throw new ToolInputError("Informe o que deve mudar.");
  return out;
}

export async function callAllAction(name: string, rawArgs: unknown, l: Ledger, today: string,
  enqueue: Enqueue): Promise<Record<string, unknown> | null> {
  const args = (rawArgs ?? {}) as Args;
  if (typeof args !== "object" || Array.isArray(args)) throw new ToolInputError("Argumentos inválidos.");
  switch (name) {
    case "get_card_invoices": {
      only(args, ["card_id", "include_transactions"]);
      const id = args.card_id === undefined ? undefined : text(account(l, str(args, "card_id", 256)).id);
      if (args.include_transactions !== undefined && typeof args.include_transactions !== "boolean") {
        throw new ToolInputError("include_transactions deve ser verdadeiro ou falso.");
      }
      return cardInvoices(l, today, id, args.include_transactions === true);
    }
    case "add_account": {
      only(args, ["name", "type", "balance", "statement_day", "due_day", "credit_limit"]);
      const type = oneOf(args, "type", accountTypes);
      const body: Args = {
        name: str(args, "name", 60), type,
        balance_cents: reais(args, "balance", { required: false, signed: true }) ?? 0,
      };
      if (type === "credit") {
        body.statement_day = dayOfMonth(args, "statement_day");
        body.due_day = dayOfMonth(args, "due_day");
        body.credit_limit_cents = reais(args, "credit_limit", { required: false });
      }
      return pending((await enqueue("account.add", body)).id, "Nova conta");
    }
    case "update_account": {
      only(args, ["id", "name", "statement_day", "due_day", "credit_limit", "exclude_from_total", "exclude_from_bank_total",
        "payment_account_id", "min_payment", "min_payment_percent", "color", "reminder_enabled", "reminder_time"]);
      const a = account(l, str(args, "id", 256));
      if (args.exclude_from_total !== undefined && typeof args.exclude_from_total !== "boolean") {
        throw new ToolInputError("exclude_from_total deve ser verdadeiro ou falso.");
      }
      const newer = ["exclude_from_bank_total", "payment_account_id", "min_payment", "min_payment_percent", "color",
        "reminder_enabled", "reminder_time"].some((k) => args[k] !== undefined) ||
        ["statement_day", "due_day", "credit_limit"].some((k) => args[k] === null);
      if (newer) {
        const credit = text(a.type) === "credit";
        const cardOnly = ["statement_day", "due_day", "credit_limit", "payment_account_id", "min_payment", "min_payment_percent",
          "reminder_enabled", "reminder_time"].filter((k) => args[k] !== undefined);
        if (!credit && cardOnly.length) throw new ToolInputError(`Só cartão de crédito tem: ${cardOnly.join(", ")}.`);
        const body: Args = { id: text(a.id) };
        const nm = str(args, "name", 60, false);
        if (nm) body.name = nm;
        for (const k of ["statement_day", "due_day"]) {
          if (args[k] !== undefined) body[k] = args[k] === null ? null : dayOfMonth(args, k);
        }
        if (args.credit_limit !== undefined) body.credit_limit_cents = args.credit_limit === null ? null : reais(args, "credit_limit");
        if (args.min_payment !== undefined) {
          body.min_payment_cents = args.min_payment === null ? null : reais(args, "min_payment");
        }
        if (args.min_payment_percent !== undefined) {
          const v = args.min_payment_percent;
          if (v !== null && (typeof v !== "number" || v < 0 || v > 100)) throw new ToolInputError("min_payment_percent de 0 a 100.");
          body.min_payment_percent = v;
        }
        if (args.payment_account_id !== undefined) {
          body.linked_account_id = args.payment_account_id === null ? null : text(account(l, str(args, "payment_account_id", 256), true).id);
          if (body.linked_account_id === text(a.id)) throw new ToolInputError("A conta de pagamento deve ser outra conta.");
        }
        for (const k of ["exclude_from_total", "exclude_from_bank_total", "reminder_enabled"]) {
          if (args[k] === undefined) continue;
          if (typeof args[k] !== "boolean") throw new ToolInputError(`${k} deve ser verdadeiro ou falso.`);
          body[k] = args[k];
        }
        if (args.reminder_time !== undefined) {
          if (typeof args.reminder_time !== "string" || !/^([01]\d|2[0-3]):[0-5]\d$/.test(args.reminder_time)) throw new ToolInputError("reminder_time deve ser HH:mm.");
          body.reminder_time = args.reminder_time;
        }
        if (args.color !== undefined) {
          if (typeof args.color !== "string" || !/^#[0-9A-Fa-f]{6}$/.test(args.color)) throw new ToolInputError("color deve ser #RRGGBB.");
          body.color = 0xFF000000 + parseInt(args.color.slice(1), 16);
        }
        return pending((await enqueue("account.edit", body)).id, "Alteração da conta");
      }
      const body = changes(args, { id: text(a.id) }, [
        ["name", (x) => str(x, "name", 60, false)],
        ["statement_day", (x) => dayOfMonth(x, "statement_day")],
        ["due_day", (x) => dayOfMonth(x, "due_day")],
        ["credit_limit_cents", (x) => reais(x, "credit_limit", { required: false })],
        ["exclude_from_total", (x) => x.exclude_from_total],
      ]);
      return pending((await enqueue("account.update", body)).id, "Alteração da conta");
    }
    case "adjust_account_balance": {
      only(args, ["account_id", "balance"]);
      const a = account(l, str(args, "account_id", 256));
      const target = reais(args, "balance", { signed: true })!;
      const expected = balanceCents(l, text(a.id));
      if (target === expected) throw new ToolInputError(`O saldo de ${text(a.name)} já é esse.`);
      const q = await enqueue("account.adjust", { id: text(a.id), expected_cents: expected, balance_cents: target });
      return {
        ...pending(q.id, "Ajuste de saldo"),
        from: money(expected), to: money(target),
        note: "Ajuste não conta como gasto nem receita. Se o saldo no aparelho mudar antes, o Nexo recusa e é preciso consultar de novo.",
      };
    }
    case "delete_account": {
      only(args, ["id"]);
      const a = account(l, str(args, "id", 256));
      return pending((await enqueue("account.delete", { id: text(a.id) })).id, "Exclusão da conta");
    }
    case "delete_category": {
      only(args, ["id"]);
      const id = str(args, "id", 256)!;
      if (!find(l.categories, id)) throw new ToolInputError("Categoria não encontrada. Use get_categories.");
      if (l.transactions.some((t) => text(t.category_id) === id) || l.recurring.some((r) => text(r.category_id) === id)) {
        throw new ToolInputError("A categoria está em uso. Mude os lançamentos dela antes de excluir.");
      }
      return pending((await enqueue("category.delete", { id })).id, "Exclusão da categoria");
    }
    case "add_goal": {
      only(args, ["name", "target", "target_date"]);
      const target = dateArg(args, "target_date");
      if (target && target <= today) throw new ToolInputError("target_date deve ser no futuro.");
      const q = await enqueue("goal.add", { name: str(args, "name", 60), target_cents: reais(args, "target"), target_date: target ?? null });
      return pending(q.id, "Novo objetivo");
    }
    case "update_goal": {
      only(args, ["id", "name", "target", "target_date", "completed", "color"]);
      const g = find(l.goals, args.id);
      if (!g) throw new ToolInputError("Objetivo não encontrado. Use get_goals.");
      if (args.completed !== undefined || args.color !== undefined || args.target_date === null) {
        const body: Args = { id: text(g.id) };
        const nm = str(args, "name", 60, false);
        if (nm) body.name = nm;
        const t = reais(args, "target", { required: false });
        if (t !== undefined) body.target_cents = t;
        if (args.target_date !== undefined) body.target_date = args.target_date === null ? null : dateArg(args, "target_date");
        if (args.completed !== undefined) {
          if (typeof args.completed !== "boolean") throw new ToolInputError("completed deve ser verdadeiro ou falso.");
          body.completed = args.completed;
        }
        if (args.color !== undefined) {
          if (typeof args.color !== "string" || !/^#[0-9A-Fa-f]{6}$/.test(args.color)) throw new ToolInputError("color deve ser #RRGGBB.");
          body.color = 0xFF000000 + parseInt(args.color.slice(1), 16);
        }
        return pending((await enqueue("goal.edit", body)).id, "Alteração do objetivo");
      }
      const body = changes(args, { id: text(g.id) }, [
        ["name", (x) => str(x, "name", 60, false)],
        ["target_cents", (x) => reais(x, "target", { required: false })],
        ["target_date", (x) => dateArg(x, "target_date")],
      ]);
      return pending((await enqueue("goal.update", body)).id, "Alteração do objetivo");
    }
    case "delete_goal": {
      only(args, ["id"]);
      const g = find(l.goals, args.id);
      if (!g) throw new ToolInputError("Objetivo não encontrado. Use get_goals.");
      if (num(g.current_amount) > 0.005) throw new ToolInputError("O objetivo ainda guarda dinheiro. Retire com move_goal antes.");
      return pending((await enqueue("goal.delete", { id: text(g.id) })).id, "Exclusão do objetivo");
    }
    case "get_investments": {
      only(args, []);
      return {
        investments: l.investments.map((i) => {
          const ops = l.investmentOperations.filter((o) => o.investment_id === i.id);
          const micros = ops.reduce((q, o) => q + (o.kind === "sell" ? -num(o.quantity) : o.kind === "income" ? 0 : num(o.quantity)), 0);
          return {
            id: text(i.id), name: text(i.name), ticker: text(i.ticker) || undefined, asset_class: text(i.asset_class),
            quantity: micros / 1e6, last_price: num(i.price_micros) / 1e6, price_date: day(text(i.price_at)),
            archived: i.archived === 1,
            operations: ops.map((o) => ({
              id: text(o.id), kind: text(o.kind), date: day(text(o.date)), quantity: num(o.quantity) / 1e6,
              total: money(num(o.cents)), cash_account_id: text(o.cash_account_id) || undefined,
            })).sort((a, b) => a.date.localeCompare(b.date)),
          };
        }),
      };
    }
    case "add_investment": {
      only(args, ["name", "asset_class", "ticker", "institution", "quantity", "total", "date", "cash_account_id"]);
      const date = dateArg(args, "date", true)!;
      if (date > today) throw new ToolInputError("date não pode ser no futuro.");
      const body: Args = {
        name: str(args, "name", 80),
        asset_class: oneOf(args, "asset_class", ["Ações", "FIIs", "ETFs", "Renda fixa", "Cripto", "Outros"]),
        ticker: str(args, "ticker", 12, false) ?? "", institution: str(args, "institution", 60, false) ?? "",
        quantity_micros: quantityMicros(args, true), cents: reais(args, "total"), date,
      };
      if (args.cash_account_id !== undefined) body.cash_account_id = text(account(l, str(args, "cash_account_id", 256), true).id);
      return pending((await enqueue("investment.add", body)).id, "Novo investimento");
    }
    case "record_investment_operation": {
      only(args, ["investment_id", "kind", "quantity", "total", "date", "cash_account_id"]);
      const inv = find(l.investments, args.investment_id);
      if (!inv) throw new ToolInputError("Investimento não encontrado. Use get_investments.");
      const kind = oneOf(args, "kind", ["buy", "sell", "income"]);
      const date = dateArg(args, "date", true)!;
      if (date > today) throw new ToolInputError("date não pode ser no futuro.");
      const body: Args = {
        investment_id: text(inv.id), kind, cents: reais(args, "total"), date,
        quantity_micros: kind === "income" ? 0 : quantityMicros(args, true),
        created_at: new Date().toISOString(),
      };
      if (kind === "income" && args.quantity !== undefined) throw new ToolInputError("Provento não tem quantidade.");
      if (args.cash_account_id !== undefined) body.cash_account_id = text(account(l, str(args, "cash_account_id", 256), true).id);
      return pending((await enqueue("investment.operation", body)).id, "Operação");
    }
    case "update_investment_price": {
      only(args, ["investment_id", "price", "date"]);
      const inv = find(l.investments, args.investment_id);
      if (!inv) throw new ToolInputError("Investimento não encontrado. Use get_investments.");
      const date = dateArg(args, "date");
      if (date && date > today) throw new ToolInputError("date não pode ser no futuro.");
      const q = await enqueue("investment.price", { investment_id: text(inv.id), price_cents: reais(args, "price"), date: date ?? null });
      return pending(q.id, "Preço");
    }
    case "get_loans": {
      only(args, []);
      return {
        loans: (l.loans ?? []).map((x) => {
          const paid = (l.loanPayments ?? []).filter((p) => p.loan_id === x.id);
          return {
            id: text(x.id), name: text(x.name), principal: money(cents(num(x.principal))),
            start: day(text(x.start_date)), end: day(text(x.end_date)),
            interest_rate_year: x.interest_rate ?? undefined,
            paid: money(paid.reduce((s, p) => s + cents(num(p.amount)), 0)),
            payments: paid.filter((p) => num(p.amount) > 0).length,
            skipped: paid.filter((p) => num(p.amount) === 0).length,
            settled: x.is_settled === 1, account_id: text(x.account_id) || undefined,
            transfer_account_id: text(x.transfer_account_id) || undefined, notes: text(x.notes) || undefined,
            payment_list: paid.map((p) => ({ id: text(p.id), date: day(text(p.date)), amount: money(cents(num(p.amount))),
              skipped: num(p.amount) === 0 })).sort((a, b) => b.date.localeCompare(a.date)).slice(0, 24),
          };
        }),
      };
    }
    case "pay_loan_installment":
    case "skip_loan_installment": {
      const paying = name === "pay_loan_installment";
      only(args, paying ? ["id", "amount", "account_id"] : ["id"]);
      const loan = find(l.loans, args.id);
      if (!loan) throw new ToolInputError("Empréstimo não encontrado. Use get_loans.");
      if (loan.is_settled === 1) throw new ToolInputError("Este empréstimo já está quitado.");
      const body: Args = { id: text(loan.id) };
      if (paying) {
        const c = reais(args, "amount", { required: false });
        if (c !== undefined) body.amount_cents = c;
        if (args.account_id !== undefined) body.account_id = text(account(l, str(args, "account_id", 256)).id);
      }
      return pending((await enqueue(paying ? "loan.pay" : "loan.skip", body)).id, paying ? "Pagamento da parcela" : "Pulo da parcela");
    }
    case "get_lended": {
      only(args, []);
      return {
        people: (l.lendedPeople ?? []).map((p) => ({ id: text(p.id), name: text(p.name), notes: text(p.notes) || undefined })),
        lended: (l.lended ?? []).map((x) => ({
          id: text(x.id), person: text(find(l.lendedPeople, x.person_id)?.name) || "Pessoa", person_id: text(x.person_id),
          account_id: text(x.account_id) || undefined, notes: text(x.notes) || undefined,
          type: text(x.type) === "borrowed" ? "peguei emprestado" : "emprestei",
          amount: money(cents(num(x.amount))), date: day(text(x.date)),
          due_date: x.due_date ? day(text(x.due_date)) : undefined, settled: x.is_settled === 1,
        })),
      };
    }
    case "add_lended": {
      only(args, ["person", "type", "amount", "account_id", "date", "due_date", "notes"]);
      const body: Args = {
        person: str(args, "person", 60), type: oneOf(args, "type", ["lent", "borrowed"]),
        amount_cents: reais(args, "amount"), date: dateArg(args, "date", true),
        due_date: dateArg(args, "due_date") ?? null, notes: str(args, "notes", 200, false) ?? "",
      };
      if (args.account_id !== undefined) body.account_id = text(account(l, str(args, "account_id", 256), true).id);
      return pending((await enqueue("lended.add", body)).id, "Registro");
    }
    case "settle_lended": {
      only(args, ["id"]);
      const x = find(l.lended, args.id);
      if (!x) throw new ToolInputError("Registro não encontrado. Use get_lended.");
      if (x.is_settled === 1) throw new ToolInputError("Já está quitado.");
      return pending((await enqueue("lended.settle", { id: text(x.id) })).id, "Quitação");
    }
    case "get_assets": {
      only(args, []);
      return {
        assets: (l.assets ?? []).map((x) => ({ id: text(x.id), name: text(x.name), value: money(cents(num(x.value))), currency: text(x.currency) })),
      };
    }
    case "add_asset": {
      only(args, ["name", "value", "notes"]);
      const q = await enqueue("asset.add", { name: str(args, "name", 60), value_cents: reais(args, "value"), notes: str(args, "notes", 200, false) ?? "" });
      return pending(q.id, "Novo bem");
    }
    case "update_asset": {
      only(args, ["id", "name", "value"]);
      const x = find(l.assets, args.id);
      if (!x) throw new ToolInputError("Bem não encontrado. Use get_assets.");
      const body = changes(args, { id: text(x.id) }, [
        ["name", (a) => str(a, "name", 60, false)],
        ["value_cents", (a) => reais(a, "value", { required: false })],
      ]);
      return pending((await enqueue("asset.update", body)).id, "Alteração do bem");
    }
    case "delete_asset": {
      only(args, ["id"]);
      const x = find(l.assets, args.id);
      if (!x) throw new ToolInputError("Bem não encontrado. Use get_assets.");
      return pending((await enqueue("asset.delete", { id: text(x.id) })).id, "Exclusão do bem");
    }
    case "get_wishlist": {
      only(args, []);
      return {
        wishlist: (l.wishlist ?? []).map((x) => ({
          id: text(x.id), name: text(x.name), price: money(cents(num(x.target_price))),
          priority: text(x.priority), purchased: x.is_purchased === 1,
        })),
      };
    }
    case "add_wishlist_item": {
      only(args, ["name", "price", "priority", "notes"]);
      const q = await enqueue("wishlist.add", {
        name: str(args, "name", 80), price_cents: reais(args, "price"),
        priority: oneOf(args, "priority", ["low", "medium", "high"], "medium"), notes: str(args, "notes", 200, false) ?? "",
      });
      return pending(q.id, "Novo desejo");
    }
    case "update_wishlist_item": {
      only(args, ["id", "name", "price", "priority", "purchased"]);
      const x = find(l.wishlist, args.id);
      if (!x) throw new ToolInputError("Item não encontrado. Use get_wishlist.");
      if (args.purchased !== undefined && typeof args.purchased !== "boolean") throw new ToolInputError("purchased deve ser verdadeiro ou falso.");
      const body = changes(args, { id: text(x.id) }, [
        ["name", (a) => str(a, "name", 80, false)],
        ["price_cents", (a) => reais(a, "price", { required: false })],
        ["priority", (a) => (a.priority === undefined ? undefined : oneOf(a, "priority", ["low", "medium", "high"]))],
        ["purchased", (a) => a.purchased],
      ]);
      return pending((await enqueue("wishlist.update", body)).id, "Alteração do desejo");
    }
    case "delete_wishlist_item": {
      only(args, ["id"]);
      const x = find(l.wishlist, args.id);
      if (!x) throw new ToolInputError("Item não encontrado. Use get_wishlist.");
      return pending((await enqueue("wishlist.delete", { id: text(x.id) })).id, "Remoção do desejo");
    }
    default:
      return null;
  }
}
