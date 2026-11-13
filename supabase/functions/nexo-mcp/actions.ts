// Tools that change the ledger. Nothing is written here: each change becomes
// a request that one of the person's devices applies with the app's own
// rules (balances, cards, transfers). The answer says "pendente" until the
// app confirms; get_request_status tells the outcome.
import { analyze, cents, day, isNeutral, type Ledger, meta, metadataIndex, money, num, type Row, text } from "./finance.ts";
import { callTool, cardLimitAlerts, ToolInputError, type ToolDefinition } from "./tools.ts";
import { callMoreAction, moreActions } from "./more_actions.ts";
import { allActions, callAllAction } from "./all_actions.ts";
import { callParityAction, extendedTransactionEdit, parityActions } from "./parity_actions.ts";

export interface Request {
  id: string;
  kind: string;
  status: "pending" | "applying" | "done" | "rejected";
  result?: Record<string, unknown> | null;
  created_at?: string;
}

export interface ActionDeps {
  /// Queues a request. The same [key] (or, without one, the same request a
  /// few minutes later) returns the first request: `deduplicated` is true.
  enqueue(kind: string, args: Record<string, unknown>, key?: string): Promise<{ id: string; status: string; deduplicated?: boolean }>;
  request(id: string): Promise<Request | null>;
  /// The connector's latest requests (absent on older servers).
  recent?(limit: number): Promise<Record<string, unknown>[]>;
  bankAccounts?(): Promise<Record<string, unknown>[]>;
  linkBankAccount?(accountId: string, nexoAccountId: string | null): Promise<number>;
  suggestions(limit: number): Promise<Record<string, unknown>[]>;
  ignoreSuggestions(ids: string[] | null, beforeMs: number | null): Promise<number>;
  /// When each bank was last refreshed (absent on older servers).
  bankStatus?(): Promise<Record<string, unknown>[]>;
  /// The queue and each device's last check (absent or null on older servers).
  queue?(): Promise<Record<string, unknown> | null>;
}

/// Devices as get_request_status shows them: version, last contact, last
/// check of the queue, and whether the server can wake it.
async function queueView(deps: ActionDeps, l: Ledger) {
  const q = deps.queue ? await deps.queue() : null;
  if (!q) {
    return { devices: (l.devices ?? []).map((d) => ({ app_version: d.app_version, last_seen: d.seen_at })) };
  }
  const devices = (q.devices as Record<string, unknown>[] ?? []).map((d) => ({
    app_version: d.app_version, last_seen: d.seen_at, last_queue_check: d.checked_at ?? undefined,
    wakes_on_request: d.push === true,
  }));
  return { devices, queue_pending: q.pending, waiting_for_app_update: Number(q.waiting_for_update ?? 0) > 0 || undefined };
}

async function waitingStep(deps: ActionDeps): Promise<string> {
  const q = deps.queue ? await deps.queue() : null;
  if (q && Number(q.waiting_for_update ?? 0) > 0) {
    return "Este pedido precisa de uma versão mais nova do Nexo do que a dos aparelhos (por exemplo, valores em dólar pedem a 1.16.0). " +
      "Ele fica na fila, sem gravar errado, até um aparelho atualizado abrir.";
  }
  const push = q && (q.devices as Record<string, unknown>[] ?? []).some((d) => d.push === true);
  return (push
    ? "O celular foi avisado e grava em segundos, mesmo com o app fechado (a economia de bateria pode atrasar). "
    : "O celular confere a fila sozinho a cada 15 minutos, mesmo com o app fechado (a economia de bateria pode atrasar); abrir o app grava na hora. ") +
    "O PC na bandeja grava em até 20 s. Em devices, last_queue_check mostra a última conferência de cada aparelho.";
}

/// "Dados do banco até…": the assistant must not read an empty day as no
/// spending when the bank simply did not send today's data yet.
async function bankFreshness(deps: ActionDeps, today: string) {
  if (!deps.bankStatus) return undefined;
  let rows: Record<string, unknown>[];
  try {
    rows = await deps.bankStatus();
  } catch {
    return undefined;
  }
  const banks = rows.map((r) => {
    const at = typeof r.bank_updated_at === "string" ? r.bank_updated_at : null;
    const local = at
      ? new Intl.DateTimeFormat("sv-SE", { timeZone: "America/Sao_Paulo", dateStyle: "short", timeStyle: "short" })
        .format(new Date(at))
      : null;
    return {
      bank: String(r.bank ?? "Banco"),
      data_until: local ?? "desconhecido",
      today_arrived: local ? local.slice(0, 10) >= today : false,
      state: r.state ?? undefined,
    };
  });
  return {
    banks,
    note: banks.some((b) => !b.today_arrived)
      ? "data_until é a última movimentação recebida de cada banco; o Open Finance atualiza uma vez por dia, então movimentações de hoje podem ainda não ter chegado. Não conclua que não houve gasto."
      : undefined,
  };
}

const dateField = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };
const amountField = { type: "number", exclusiveMinimum: 0, maximum: 1000000000, description: "Valor em reais, positivo (ex.: 32.90)" };

const baseActions: (ToolDefinition & { destructive?: boolean })[] = [
  {
    name: "add_transaction",
    title: "Lançar despesa ou receita",
    description:
      "Registra uma despesa ou receita numa conta. Use get_accounts e get_categories para os ids. Opcional: subcategoria, " +
      "pendente com vencimento (ainda não sai do saldo), gasto pontual e parcelas (o valor total dividido em N meses). " +
      "O Nexo grava pelo app (celular ou PC aberto) com as regras normais; confira com get_request_status antes de dizer que foi lançado.",
    inputSchema: {
      type: "object",
      properties: {
        type: { type: "string", enum: ["expense", "income"] },
        amount: amountField,
        description: { type: "string", minLength: 1, maxLength: 80 },
        account_id: { type: "string" },
        category_id: { type: "string" },
        date: { ...dateField, description: "AAAA-MM-DD; padrão: hoje" },
        note: { type: "string", maxLength: 200 },
        subcategory: { type: "string", maxLength: 60 },
        status: { type: "string", enum: ["paid", "pending"], description: "pending: conta a pagar/receber, não sai do saldo" },
        due_date: { ...dateField, description: "Vencimento (pendentes); padrão: a data" },
        kind: { type: "string", enum: ["normal", "extraordinary"], description: "extraordinary = gasto pontual" },
        installments: { type: "integer", minimum: 2, maximum: 120, description: "Divide o valor total em N parcelas mensais" },
      },
      required: ["type", "amount", "description", "account_id", "category_id"],
      additionalProperties: false,
    },
  },
  {
    name: "add_transactions",
    title: "Lançar vários de uma vez",
    description:
      "Vários lançamentos numa chamada (ex.: os itens de um print ou de um extrato), cada um como em add_transaction. " +
      "Todos são conferidos antes: se um tiver erro, nenhum é enviado. dry_run: true mostra o que seria lançado e os " +
      "possíveis duplicados (mesmo valor e tipo em até 3 dias, em qualquer conta), sem enviar nada. Reenviar o mesmo lote não duplica.",
    inputSchema: {
      type: "object",
      properties: {
        items: {
          type: "array", minItems: 1, maxItems: 20,
          items: {
            type: "object",
            properties: {
              type: { type: "string", enum: ["expense", "income"] },
              amount: amountField,
              description: { type: "string", minLength: 1, maxLength: 80 },
              account_id: { type: "string" },
              category_id: { type: "string" },
              date: { ...dateField, description: "AAAA-MM-DD; padrão: hoje" },
              note: { type: "string", maxLength: 200 },
              subcategory: { type: "string", maxLength: 60 },
              status: { type: "string", enum: ["paid", "pending"] },
              due_date: dateField,
              kind: { type: "string", enum: ["normal", "extraordinary"] },
            },
            required: ["type", "amount", "description", "account_id", "category_id"],
            additionalProperties: false,
          },
        },
        dry_run: { type: "boolean", description: "true: só confere e mostra; nada é enviado" },
      },
      required: ["items"],
      additionalProperties: false,
    },
  },
  {
    name: "add_transfer",
    title: "Transferir entre contas",
    description:
      "Move dinheiro entre duas contas da pessoa (não é gasto nem receita). Use também para pagar fatura de cartão a partir de uma conta.",
    inputSchema: {
      type: "object",
      properties: {
        from_account_id: { type: "string" },
        to_account_id: { type: "string" },
        amount: amountField,
        received_amount: {
          ...amountField,
          description: "Câmbio entre contas de moedas diferentes: quanto chegou na conta de destino, na moeda dela (ex.: dólares creditados no Inter Global). Obrigatório nesse caso; a taxa efetiva, com spread e IOF, sai daí.",
        },
        date: dateField,
        note: { type: "string", maxLength: 200 },
      },
      required: ["from_account_id", "to_account_id", "amount"],
      additionalProperties: false,
    },
  },
  {
    name: "update_transaction",
    title: "Editar lançamento",
    description:
      "Edita qualquer campo de um lançamento: valor, descrição, categoria, conta, data, observação, tipo (despesa/receita), " +
      "subcategoria, situação (paid/pending), vencimento, gasto pontual (kind extraordinary) e se é a renda do mês " +
      "(recurring_income_id). Transferências e investimentos têm ferramentas próprias.",
    destructive: true,
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string" },
        amount: amountField,
        description: { type: "string", minLength: 1, maxLength: 80 },
        category_id: { type: "string" },
        account_id: { type: "string" },
        date: dateField,
        note: { type: "string", maxLength: 200 },
        type: { type: "string", enum: ["expense", "income"] },
        subcategory: { type: "string", maxLength: 60 },
        status: { type: "string", enum: ["paid", "pending"], description: "pending: ainda não saiu do saldo" },
        due_date: { type: ["string", "null"], description: "Vencimento AAAA-MM-DD (pendentes); null tira" },
        kind: { type: "string", enum: ["normal", "extraordinary"], description: "extraordinary = gasto pontual, fora das médias" },
        recurring_income_id: { type: "string", description: "Conta esta receita como a ocorrência desta receita recorrente (\"é a renda do mês\")" },
      },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "delete_transaction",
    title: "Apagar lançamento",
    description: "Apaga um lançamento (o saldo da conta é ajustado). Transferências são apagadas nas duas pontas.",
    destructive: true,
    inputSchema: {
      type: "object",
      properties: { id: { type: "string" } },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "list_suggestions",
    title: "Sugestões do Open Finance",
    description:
      "Lista movimentações dos bancos conectados (Meu Pluggy) que ainda esperam revisão. Nenhuma virou lançamento ainda.",
    inputSchema: {
      type: "object",
      properties: { limit: { type: "integer", minimum: 1, maximum: 200, description: "Padrão 30" } },
      additionalProperties: false,
    },
  },
  {
    name: "confirm_suggestion",
    title: "Confirmar sugestão",
    description:
      "Transforma uma sugestão do Open Finance em lançamento, com a conta e a categoria escolhidas. Antes, procure em list_transactions se já não existe o mesmo lançamento.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "id da sugestão (pluggy:...)" },
        account_id: { type: "string" },
        category_id: { type: "string" },
        type: { type: "string", enum: ["expense", "income"], description: "Padrão: o tipo sugerido pelo banco" },
        description: { type: "string", minLength: 1, maxLength: 80 },
        subcategory: { type: "string", maxLength: 60 },
        note: { type: "string", maxLength: 200 },
        allow_duplicate: { type: "boolean", description: "true: confirma mesmo havendo lançamento parecido (gastos diferentes de mesmo valor)" },
      },
      required: ["id", "account_id", "category_id"],
      additionalProperties: false,
    },
  },
  {
    name: "ignore_suggestions",
    title: "Ignorar sugestões",
    description:
      "Descarta sugestões do Open Finance sem lançar nada: por ids, ou todas anteriores a uma data. Não mexe em saldos.",
    inputSchema: {
      type: "object",
      properties: {
        ids: { type: "array", items: { type: "string" }, maxItems: 200 },
        before: { ...dateField, description: "Ignora todas com data anterior a esta" },
        preview: { type: "boolean", description: "true: só mostra quantas e quais seriam ignoradas" },
      },
      additionalProperties: false,
    },
  },
  {
    name: "get_daily_digest",
    title: "Resumo do dia",
    description:
      "Como foi o dia: o que entrou, o que saiu, compras no cartão, orçamentos estourados, próximos vencimentos e se os dados do banco de hoje já chegaram. Padrão: hoje.",
    inputSchema: {
      type: "object",
      properties: { date: { ...dateField, description: "Dia (AAAA-MM-DD); padrão hoje" } },
      additionalProperties: false,
    },
  },
  {
    name: "get_bank_sync_status",
    title: "Dados do banco até quando",
    description:
      "Para cada banco do Open Finance: até quando os dados chegaram e se os de hoje já vieram. Consulte antes de afirmar que não houve gastos em um dia.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "get_request_status",
    title: "Situação de um pedido",
    description: "Diz se um pedido de lançamento, correção ou exclusão já foi gravado pelo Nexo, ainda está na fila (com a última conferência de cada aparelho) ou foi recusado (com o motivo).",
    inputSchema: {
      type: "object",
      properties: { id: { type: "string" } },
      required: ["id"],
      additionalProperties: false,
    },
  },
];

type Args = Record<string, unknown>;

function only(args: Args, allowed: string[]) {
  const extra = Object.keys(args).filter((k) => !allowed.includes(k));
  if (extra.length) throw new ToolInputError(`Parâmetros não suportados: ${extra.join(", ")}.`);
}

function str(args: Args, key: string, max: number, required = true): string | undefined {
  const v = args[key];
  if (v === undefined && !required) return undefined;
  if (typeof v !== "string" || !v.trim() || v.length > max) {
    throw new ToolInputError(`${key} é obrigatório (até ${max} caracteres).`);
  }
  return v.trim();
}

function amountCents(args: Args, required = true): number | undefined {
  const v = args.amount;
  if (v === undefined && !required) return undefined;
  if (typeof v !== "number" || !isFinite(v) || v <= 0 || v > 1e9) {
    throw new ToolInputError("amount deve ser um valor positivo em reais.");
  }
  const cents = Math.round(v * 100);
  if (Math.abs(cents - v * 100) > 1e-6) throw new ToolInputError("amount aceita no máximo 2 casas decimais.");
  return cents;
}

function date(args: Args, key: string, today: string, required = false): string | undefined {
  const v = args[key];
  if (v === undefined) return required ? today : undefined;
  if (typeof v !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(v) || isNaN(Date.parse(`${v}T00:00:00Z`))) {
    throw new ToolInputError(`${key} deve estar no formato AAAA-MM-DD.`);
  }
  return v;
}

function account(l: Ledger, id: string | undefined) {
  const a = l.accounts.find((x) => text(x.id) === id);
  if (!a) throw new ToolInputError("Conta não encontrada. Use get_accounts para ver os ids.");
  return a;
}

function category(l: Ledger, id: string | undefined, type: string) {
  const c = l.categories.find((x) => text(x.id) === id);
  if (!c) throw new ToolInputError("Categoria não encontrada. Use get_categories para ver os ids.");
  // A type is unknown only for something still being created; the app checks.
  if (type && text(c.type) && text(c.type) !== type) {
    throw new ToolInputError(`A categoria ${text(c.name)} é de ${text(c.type) === "income" ? "receita" : "despesa"}.`);
  }
  return c;
}

/// Investment cash keeps its money in step with the portfolio, so only what
/// does not touch money can change here.
const investmentCashFields = ["id", "category_id", "description", "note"];

function editable(l: Ledger, id: string, args?: Args) {
  const tx = l.transactions.find((t) => text(t.id) === id);
  if (!tx) throw new ToolInputError("Lançamento não encontrado. Use list_transactions para ver os ids.");
  const m = meta(metadataIndex(l).get(id));
  if (id.startsWith("investment:") || m.source.startsWith("investment:")) {
    if (!args || Object.keys(args).some((k) => !investmentCashFields.includes(k))) {
      throw new ToolInputError(
        "Numa movimentação de investimento só categoria, descrição e observação mudam aqui. Valor, conta e data são alterados na aba Investir do app.");
    }
  }
  return tx;
}

const pending = (id: string, what: string) => ({
  request_id: id,
  status: "pendente",
  message: `Pedido enviado ao Nexo (${what}). O celular ou o PC grava sozinho, mesmo com o app fechado (em segundos com o aviso do servidor, ou na checagem de 15 em 15 min); confira com get_request_status.`,
});

const statusText: Record<string, string> = {
  pending: "pendente: na fila, aguardando um aparelho gravar",
  applying: "em andamento no app",
  done: "gravado no Nexo",
  rejected: "recusado pelo Nexo",
};

export const actions: (ToolDefinition & { destructive?: boolean })[] = [
  ...baseActions, ...moreActions, ...allActions, ...parityActions,
];

/// Ids the app gives to what a request creates, so a later request can use
/// it before the first one is recorded (requests are applied in order).
export const createdIdPrefix: Record<string, string> = {
  "transaction.add": "assistant:", "transaction.create": "assistant:", "category.add": "assistant-cat:", "account.add": "assistant-acc:",
  "goal.add": "assistant-goal:", "recurring.add": "assistant-rec:", "investment.add": "assistant-inv:",
  "loan.add": "assistant-loan:", "lended.add": "assistant-lend:", "asset.add": "assistant-asset:",
  "wishlist.add": "assistant-wish:", "rule.save": "assistant-rule:",
};

/// What a tool may reference before it reaches the ledger. Recurring entries
/// and loans stay out: their tools compute with the stored amounts, which a
/// placeholder does not have.
const pendingTargets: Record<string, { kinds: string[]; rows: keyof Ledger }> = {
  "assistant": { kinds: ["transaction.add", "transaction.create"], rows: "transactions" },
  "assistant-cat": { kinds: ["category.add"], rows: "categories" },
  "assistant-acc": { kinds: ["account.add"], rows: "accounts" },
  "assistant-goal": { kinds: ["goal.add"], rows: "goals" },
  "assistant-inv": { kinds: ["investment.add"], rows: "investments" },
  "assistant-lend": { kinds: ["lended.add"], rows: "lended" },
  "assistant-asset": { kinds: ["asset.add"], rows: "assets" },
  "assistant-wish": { kinds: ["wishlist.add"], rows: "wishlist" },
};

/// Ledger with placeholders for things that pending requests will create,
/// so tools accept their ids (e.g. a category created a moment ago, or an
/// entry to fix). The same goes for a request already recorded whose result
/// has not synced yet. Requests are applied in order, and the app checks.
async function withPending(l: Ledger, args: Record<string, unknown>, deps: ActionDeps): Promise<Ledger> {
  const refs = new Set<string>();
  const scan = (v: unknown) => {
    if (typeof v === "string" && /^assistant(-[a-z]+)?:[0-9a-f-]{36}$/.test(v)) refs.add(v);
    else if (Array.isArray(v)) v.forEach(scan);
    else if (v && typeof v === "object") Object.values(v).forEach(scan);
  };
  scan(args);
  if (!refs.size) return l;
  const out = { ...l } as Ledger;
  for (const ref of refs) {
    const [prefix, id] = ref.split(":");
    const target = pendingTargets[prefix];
    if (!target) continue;
    const known = [...((out[target.rows] ?? []) as Row[])];
    if (known.some((r) => r.id === ref)) continue;
    const r = await deps.request(id);
    if (!r || !target.kinds.includes(r.kind) || r.status === "rejected") continue;
    known.push({ id: ref, name: "(sendo criado)", type: "", currency: l.mainCurrency });
    (out as unknown as Record<string, Row[]>)[target.rows] = known;
  }
  return out;
}

/// Server refusals the assistant can act on, instead of a generic failure.
function guarded(deps: ActionDeps, key?: string, seen?: { kind?: string; id?: string; deduplicated?: boolean }): ActionDeps {
  return {
    ...deps,
    enqueue: async (kind, args) => {
      try {
        const r = await deps.enqueue(kind, args, key);
        if (seen) Object.assign(seen, { kind, id: r.id, deduplicated: r.deduplicated === true });
        return r;
      } catch (error) {
        const reason = error instanceof Error ? error.message : "";
        if (reason.includes("idempotency_key_reused")) {
          throw new ToolInputError("Esta idempotency_key já foi usada num pedido diferente. Use outra chave.");
        }
        if (reason.includes("kind_unsupported")) {
          throw new ToolInputError(
            "O Nexo instalado no celular/PC ainda não sabe fazer isto. Atualize o app e abra-o uma vez; depois peça de novo.");
        }
        if (reason.includes("too_many_pending")) {
          throw new ToolInputError(
            "Há 100 pedidos esperando um aparelho com o Nexo aberto. Abra o app no celular ou no PC e espere eles serem gravados.");
        }
        throw error;
      }
    },
  };
}

export async function callAction(name: string, rawArgs: unknown, ledger: Ledger, today: string,
  rawDeps: ActionDeps): Promise<Record<string, unknown>> {
  const given = (rawArgs ?? {}) as Args;
  if (typeof given !== "object" || Array.isArray(given)) throw new ToolInputError("Argumentos inválidos.");
  // A key per request makes resending it safe; it never reaches the app.
  const { idempotency_key: key, ...args } = given;
  if (key !== undefined && (typeof key !== "string" || !key.trim() || key.length > 120)) {
    throw new ToolInputError("idempotency_key deve ter de 1 a 120 caracteres.");
  }
  if (name === "add_transactions") return await addMany(args, ledger, today, rawDeps, key as string | undefined);
  const seen: { kind?: string; id?: string; deduplicated?: boolean } = {};
  const deps = guarded(rawDeps, key as string | undefined, seen);
  const l = await withPending(ledger, args, rawDeps);
  const result = await dispatchAction(name, args, l, today, deps);
  if (name === "add_transaction") {
    const twins = similarTransactions(l, args);
    if (twins.length) {
      result.possible_duplicates = twins;
      result.duplicate_note = "Já existe lançamento com o mesmo valor em até 3 dias. Se for o mesmo gasto, desfaça este com undo_request ou apague o outro.";
    }
  }
  if (seen.id && typeof result.request_id === "string") {
    const prefix = createdIdPrefix[seen.kind ?? ""];
    if (prefix && !result.new_id) result.new_id = `${prefix}${seen.id}`;
    if (seen.deduplicated) {
      result.deduplicated = true;
      result.message = "Este mesmo pedido já tinha sido enviado; nada foi duplicado. Situação: veja get_request_status.";
    }
  }
  return result;
}

/// Entries already in the ledger that look like [args]: same type and
/// amount, within 3 days, in any account (an iFood paid by Pix but typed as
/// card is still the same lunch).
export function similarTransactions(l: Ledger, args: Args) {
  const cents = typeof args.amount === "number" ? Math.round(args.amount * 100) : NaN;
  const day = typeof args.date === "string" ? Date.parse(`${args.date}T12:00:00Z`) : NaN;
  if (!Number.isFinite(cents) || !Number.isFinite(day)) return [];
  const names = new Map((l.accounts ?? []).map((a) => [text(a.id), text(a.name)]));
  return (l.transactions ?? [])
    .filter((t) => t.type === args.type && Math.round(Math.abs(Number(t.amount)) * 100) === cents &&
      Math.abs(Date.parse(`${text(t.date).slice(0, 10)}T12:00:00Z`) - day) <= 3 * 86400000)
    .slice(0, 3)
    .map((t) => ({ id: t.id, date: text(t.date).slice(0, 10), description: t.description,
      account: names.get(text(t.account_id)) ?? t.account_id }));
}

async function digest(text: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(bytes)].slice(0, 12).map((b) => b.toString(16).padStart(2, "0")).join("");
}

/// add_transactions: every item is checked first (all or nothing), then each
/// becomes its own request, in order. Keys come from the batch content, so
/// resending the same batch never duplicates, while two equal items in it
/// (two coffees) stay two entries.
async function addMany(args: Args, ledger: Ledger, today: string, deps: ActionDeps, key?: string) {
  only(args, ["items", "dry_run"]);
  const items = args.items;
  if (!Array.isArray(items) || items.length < 1 || items.length > 20) throw new ToolInputError("items: de 1 a 20 lançamentos.");
  if (args.dry_run !== undefined && typeof args.dry_run !== "boolean") throw new ToolInputError("dry_run deve ser verdadeiro ou falso.");
  const l = await withPending(ledger, args, deps);
  const dry: ActionDeps = { ...deps, enqueue: async () => ({ id: "00000000-0000-4000-8000-000000000000", status: "pending" }) };
  const checked = [];
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    if (!item || typeof item !== "object" || Array.isArray(item)) throw new ToolInputError(`Item ${i + 1}: formato inválido.`);
    try {
      await dispatchAction("add_transaction", { ...(item as Args) }, l, today, dry);
    } catch (error) {
      throw new ToolInputError(`Item ${i + 1}: ${error instanceof Error ? error.message : "inválido"} Nada foi enviado.`);
    }
    const it = item as Args;
    const twins = similarTransactions(l, { ...it, date: it.date ?? today });
    const inBatch = items.slice(0, i).findIndex((o) => {
      const other = o as Args;
      return other.type === it.type && other.amount === it.amount && (other.date ?? today) === (it.date ?? today);
    });
    checked.push({
      index: i + 1, type: it.type, amount: it.amount, description: it.description, date: it.date ?? today,
      account_id: it.account_id,
      ...(twins.length ? { possible_duplicates: twins } : {}),
      ...(inBatch >= 0 ? { same_as_item: inBatch + 1 } : {}),
    });
  }
  if (args.dry_run === true) {
    return {
      dry_run: true, items: checked,
      note: "Prévia: nada foi enviado. Confira os possíveis duplicados e chame de novo sem dry_run.",
    };
  }
  const base = key ?? `lote-${await digest(JSON.stringify(items))}`;
  const requests = [];
  for (let i = 0; i < items.length; i++) {
    const r = await callAction("add_transaction", { ...(items[i] as Args), idempotency_key: `${base}#${i + 1}` }, ledger, today, deps);
    requests.push({ index: i + 1, request_id: r.request_id, new_id: r.new_id, deduplicated: r.deduplicated ?? undefined,
      possible_duplicates: checked[i].possible_duplicates });
  }
  return {
    status: "pendente", requests,
    message: `${items.length} pedidos enviados ao Nexo, gravados na ordem. Confira com get_request_status ou list_requests.`,
  };
}

async function dispatchAction(name: string, args: Args, l: Ledger, today: string,
  deps: ActionDeps): Promise<Record<string, unknown>> {
  switch (name) {
    case "add_transaction": {
      only(args, ["type", "amount", "description", "account_id", "category_id", "date", "note", "subcategory", "status",
        "due_date", "kind", "installments"]);
      const type = args.type;
      if (type !== "expense" && type !== "income") throw new ToolInputError("type deve ser expense ou income.");
      const a = account(l, str(args, "account_id", 256));
      category(l, str(args, "category_id", 256), type);
      const body: Args = {
        type, amount_cents: amountCents(args), description: str(args, "description", 80),
        account_id: text(a.id), category_id: args.category_id, date: date(args, "date", today, true),
        note: str(args, "note", 200, false) ?? "",
      };
      // The newer fields travel in the newer request kind (older apps do not know them).
      const extended = ["subcategory", "status", "due_date", "kind", "installments"].some((k) => args[k] !== undefined);
      if (extended) {
        if (args.subcategory !== undefined) body.subcategory = str(args, "subcategory", 60, false) ?? "";
        if (args.status !== undefined) {
          if (args.status !== "paid" && args.status !== "pending") throw new ToolInputError("status deve ser paid ou pending.");
          body.status = args.status;
        }
        if (args.due_date !== undefined) body.due_date = date(args, "due_date", today);
        if (args.kind !== undefined) {
          if (args.kind !== "normal" && args.kind !== "extraordinary") throw new ToolInputError("kind deve ser normal ou extraordinary.");
          body.expense_class = args.kind;
        }
        if (args.installments !== undefined) {
          const n = args.installments;
          if (typeof n !== "number" || !Number.isInteger(n) || n < 2 || n > 120) throw new ToolInputError("installments de 2 a 120.");
          body.installments = n;
        }
        const r = await deps.enqueue("transaction.create", body);
        return pending(r.id, type === "expense" ? "Despesa" : "Receita");
      }
      const r = await deps.enqueue("transaction.add", body);
      return pending(r.id, type === "expense" ? "Despesa" : "Receita");
    }
    case "add_transfer": {
      only(args, ["from_account_id", "to_account_id", "amount", "received_amount", "date", "note"]);
      const from = account(l, str(args, "from_account_id", 256));
      const to = account(l, str(args, "to_account_id", 256));
      if (text(from.id) === text(to.id)) throw new ToolInputError("Escolha contas diferentes.");
      const exchange = (text(from.currency) || l.mainCurrency) !== (text(to.currency) || l.mainCurrency);
      if (exchange && args.received_amount === undefined) {
        throw new ToolInputError(`Câmbio de ${text(from.currency)} para ${text(to.currency)}: informe received_amount, o valor que chegou na conta de destino.`);
      }
      if (!exchange && args.received_amount !== undefined) {
        throw new ToolInputError("received_amount só vale entre contas de moedas diferentes.");
      }
      const body: Record<string, unknown> = {
        from_account_id: text(from.id), to_account_id: text(to.id), amount_cents: amountCents(args),
        date: date(args, "date", today, true), note: str(args, "note", 200, false) ?? "",
      };
      if (exchange) {
        try {
          body.received_cents = amountCents({ amount: args.received_amount });
        } catch {
          throw new ToolInputError("received_amount deve ser um valor positivo, com até 2 casas, na moeda da conta de destino.");
        }
      }
      const r = await deps.enqueue("transfer.add", body);
      return pending(r.id, exchange ? "Câmbio" : "Transferência");
    }
    case "update_transaction": {
      only(args, ["id", "amount", "description", "category_id", "account_id", "date", "note", "type", "subcategory",
        "status", "due_date", "kind", "recurring_income_id"]);
      const id = str(args, "id", 256)!;
      const tx = editable(l, id, args);
      if (meta(metadataIndex(l).get(id)).source.startsWith("transfer:")) {
        throw new ToolInputError("Para mudar uma transferência, apague-a (as duas pontas) e registre de novo.");
      }
      // New fields use the newer request kind; old ones keep the old kind.
      const extended = extendedTransactionEdit(l, args);
      if (extended) return pending((await deps.enqueue("transaction.edit", extended)).id, "Edição");
      const change: Args = { id };
      const cents = amountCents(args, false);
      if (cents !== undefined) change.amount_cents = cents;
      const desc = str(args, "description", 80, false);
      if (desc !== undefined) change.description = desc;
      if (args.account_id !== undefined) change.account_id = text(account(l, str(args, "account_id", 256)).id);
      if (args.category_id !== undefined) {
        category(l, str(args, "category_id", 256), text(tx.type));
        change.category_id = args.category_id;
      }
      const d = date(args, "date", today);
      if (d !== undefined) change.date = d;
      const note = str(args, "note", 200, false);
      if (note !== undefined) change.note = note;
      if (Object.keys(change).length === 1) throw new ToolInputError("Informe o que deve mudar.");
      const r = await deps.enqueue("transaction.update", change);
      return pending(r.id, "Correção");
    }
    case "delete_transaction": {
      only(args, ["id"]);
      const id = str(args, "id", 256)!;
      editable(l, id);
      const r = await deps.enqueue("transaction.delete", { id });
      return pending(r.id, "Exclusão");
    }
    case "list_suggestions": {
      only(args, ["limit"]);
      const limit = args.limit === undefined ? 30 : args.limit;
      if (typeof limit !== "number" || !Number.isInteger(limit) || limit < 1 || limit > 200) {
        throw new ToolInputError("limit deve ser um inteiro entre 1 e 200.");
      }
      const rows = await deps.suggestions(limit);
      const metas = metadataIndex(l);
      const credit = new Set(l.accounts.filter((x) => x.type === "credit").map((x) => text(x.id)));
      const used = new Set<string>();
      /// Same direction, same amount, three days apart at most: most likely
      /// recorded by hand. The kind of account decides if it is really right.
      const recorded = (s: Record<string, unknown>) => {
        const when = new Date(Number(s.occurred_at)).toISOString().slice(0, 10);
        const type = s.kind === "income" || s.kind === "refund" ? "income" : "expense";
        const near = l.transactions.find((t) => !used.has(text(t.id)) && t.type === type &&
          cents(num(t.amount)) === Number(s.amount_cents) && !isNeutral(t, meta(metas.get(text(t.id)))) &&
          Math.abs(Date.parse(day(text(t.date))) - Date.parse(when)) <= 3 * 86400000);
        if (!near) return undefined;
        used.add(text(near.id));
        return {
          id: text(near.id), description: text(near.description),
          account_mismatch: (s.medium === "credit") !== credit.has(text(near.account_id)),
        };
      };
      return {
        suggestions: rows.map((s) => ({
          id: s.id, bank: s.bank, date: new Date(Number(s.occurred_at)).toISOString().slice(0, 10),
          amount: Number(s.amount_cents) / 100, kind: s.kind, medium: s.medium === "credit" ? "cartão" : "conta",
          description: s.description, settled: s.settled, installment: s.installment ?? undefined,
          probably_recorded: recorded(s),
        })),
        note: "Sugestões não são lançamentos. Confirme as que são reais com confirm_suggestion e descarte o resto com ignore_suggestions.",
        bank_data: await bankFreshness(deps, today),
      };
    }
    case "confirm_suggestion": {
      only(args, ["id", "account_id", "category_id", "type", "description", "subcategory", "note", "allow_duplicate"]);
      const id = str(args, "id", 80)!;
      if (!/^pluggy:[0-9A-Za-z-]{1,64}$/.test(id)) throw new ToolInputError("id de sugestão inválido.");
      if (args.allow_duplicate !== undefined && typeof args.allow_duplicate !== "boolean") {
        throw new ToolInputError("allow_duplicate deve ser verdadeiro ou falso.");
      }
      // A bank movement already typed by hand (the R$ 37 lunch, an iFood
      // paid by Pix but entered on the card) must not become a second entry.
      if (args.allow_duplicate !== true) {
        const s = (await deps.suggestions(200)).find((x) => String(x.id) === id);
        if (s) {
          const kind = s.kind === "income" ? "income" : "expense";
          const day = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo" })
            .format(new Date(Number(s.occurred_at)));
          const twins = similarTransactions(l, { type: kind, amount: Number(s.amount_cents) / 100, date: day });
          if (twins.length) {
            return {
              status: "não enviado",
              possible_duplicates: twins,
              message: "Já existe lançamento com o mesmo valor em até 3 dias; confirmar criaria outro. Se for o mesmo gasto, " +
                "ignore a sugestão (ignore_suggestions) e, se a conta estiver errada, corrija o lançamento existente. " +
                "Se forem gastos diferentes, chame de novo com allow_duplicate: true.",
            };
          }
        }
      }
      const type = args.type;
      if (type !== undefined && type !== "expense" && type !== "income") {
        throw new ToolInputError("type deve ser expense ou income.");
      }
      const a = account(l, str(args, "account_id", 256));
      const c = category(l, str(args, "category_id", 256), typeof type === "string" ? type : text(
        l.categories.find((x) => text(x.id) === args.category_id)?.type));
      const fields = {
        id, account_id: text(a.id), category_id: text(c.id), type: type ?? text(c.type),
        description: str(args, "description", 80, false),
      };
      const extra = args.subcategory !== undefined || args.note !== undefined;
      const r = await deps.enqueue(extra ? "suggestion.accept" : "suggestion.confirm", extra
        ? { ...fields, subcategory: str(args, "subcategory", 60, false), note: str(args, "note", 200, false) }
        : fields);
      return pending(r.id, "Confirmação da sugestão");
    }
    case "ignore_suggestions": {
      only(args, ["ids", "before", "preview"]);
      const ids = args.ids;
      if (args.preview !== undefined && typeof args.preview !== "boolean") {
        throw new ToolInputError("preview deve ser verdadeiro ou falso.");
      }
      if (ids !== undefined && (!Array.isArray(ids) || ids.length > 200 || ids.some((i) => typeof i !== "string"))) {
        throw new ToolInputError("ids deve ser uma lista de até 200 ids.");
      }
      const before = date(args, "before", today);
      if ((!ids || ids.length === 0) && !before) throw new ToolInputError("Informe ids ou before.");
      if (args.preview === true) {
        // What would be ignored, without changing anything.
        const beforeMs = before ? Date.parse(`${before}T00:00:00-03:00`) : null;
        const hit = (await deps.suggestions(200)).filter((s) =>
          ids?.length ? (ids as string[]).includes(String(s.id)) : Number(s.occurred_at) < beforeMs!);
        return {
          would_ignore: hit.length,
          total_value: Math.round(hit.reduce((t, s) => t + Number(s.amount_cents), 0)) / 100,
          items: hit.slice(0, 50).map((s) => ({
            id: s.id, date: new Date(Number(s.occurred_at)).toISOString().slice(0, 10),
            amount: Number(s.amount_cents) / 100, description: s.description,
          })),
          note: "Prévia: nada foi alterado. Chame de novo sem preview para aplicar.",
        };
      }
      const count = await deps.ignoreSuggestions(ids?.length ? ids as string[] : null,
        before ? Date.parse(`${before}T00:00:00-03:00`) : null);
      return { ignored: count, message: `${count} sugestão(ões) descartada(s). Nenhum saldo mudou.` };
    }
    case "get_daily_digest": {
      only(args, ["date"]);
      const d = date(args, "date", today) ?? today;
      if (d > today) throw new ToolInputError("date não pode ser no futuro.");
      const a = analyze(l, { from: d, to: d });
      const metas = metadataIndex(l);
      const credit = new Set(l.accounts.filter((x) => x.type === "credit").map((x) => text(x.id)));
      const ofDay = l.transactions.filter((t) => day(text(t.date)) === d &&
        meta(metas.get(text(t.id))).status !== "pending" && !isNeutral(t, meta(metas.get(text(t.id)))));
      const item = (t: typeof ofDay[number]) => ({
        description: text(t.description), amount: money(cents(num(t.amount))),
        category: l.categories.find((c) => c.id === t.category_id)?.name ?? undefined,
      });
      const budgets = (await callMoreAction("get_budgets", {}, l, today, deps.enqueue))?.budgets as
        { category: string; used_percent: number | null; remaining: number }[] | undefined;
      const upcoming = callTool("get_upcoming_bills", { days: 3 }, l, today) as Record<string, unknown[]>;
      return {
        date: d,
        income: money(a.income), expense: money(a.expense),
        incomes: ofDay.filter((t) => t.type === "income").map(item),
        expenses: ofDay.filter((t) => t.type === "expense" && !credit.has(text(t.account_id))).map(item),
        card_purchases: ofDay.filter((t) => t.type === "expense" && credit.has(text(t.account_id))).map(item),
        budgets_over: (budgets ?? []).filter((b) => (b.used_percent ?? 0) >= 100)
          .map((b) => ({ category: b.category, used_percent: b.used_percent })),
        due_next_3_days: [...(upcoming.pending_expenses ?? []), ...(upcoming.recurring_expected ?? [])],
        card_limit_alerts: cardLimitAlerts(l, today),
        bank_data: await bankFreshness(deps, today),
        note: "Transferências, reservas e pendentes não contam como gasto. Se bank_data disser que hoje ainda não chegou, gastos do banco podem faltar.",
      };
    }
    case "get_bank_sync_status": {
      only(args, []);
      return (await bankFreshness(deps, today)) ??
        { banks: [], note: "O servidor ainda não informa a data dos dados do banco." };
    }
    case "get_request_status": {
      only(args, ["id"]);
      const id = str(args, "id", 64)!;
      if (!/^[0-9a-f-]{36}$/.test(id)) throw new ToolInputError("id de pedido inválido.");
      const r = await deps.request(id);
      if (!r) throw new ToolInputError("Pedido não encontrado.");
      const waiting = r.status === "pending" || r.status === "applying";
      const minutes = waiting && r.created_at ? Math.max(0, Math.round((Date.now() - Date.parse(r.created_at)) / 60000)) : undefined;
      // What the request changed stays on the server for undo_request.
      const { undo, undone_at, undone_by: _by, ...shown } = (r.result ?? {}) as Record<string, unknown>;
      return {
        request_id: r.id, kind: r.kind,
        status: undone_at ? "gravado no Nexo e depois desfeito" : statusText[r.status] ?? r.status,
        result: r.result ? shown : undefined,
        undoable: r.status === "done" && !undone_at && !!undo && !(undo as Record<string, unknown>).too_large,
        undone_at: undone_at ?? undefined,
        waiting_minutes: minutes,
        // Who could record it and when each device last looked at the queue.
        ...(waiting ? await queueView(deps, l) : {}),
        next_step: !waiting ? undefined : r.status === "applying"
          ? "Um aparelho está gravando agora; consulte de novo em alguns segundos."
          : await waitingStep(deps),
      };
    }
    default: {
      const more = await callMoreAction(name, args, l, today, deps.enqueue) ??
        await callAllAction(name, args, l, today, deps.enqueue) ??
        await callParityAction(name, args, l, today, deps);
      if (more) return more;
      throw new ToolInputError("Ferramenta desconhecida.");
    }
  }
}
