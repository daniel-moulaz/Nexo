// Tools that change the ledger. Nothing is written here: each change becomes
// a request that one of the person's devices applies with the app's own
// rules (balances, cards, transfers). The answer says "pendente" until the
// app confirms; get_request_status tells the outcome.
import { type Ledger, meta, metadataIndex, text } from "./finance.ts";
import { ToolInputError, type ToolDefinition } from "./tools.ts";
import { callMoreAction, moreActions } from "./more_actions.ts";
import { allActions, callAllAction } from "./all_actions.ts";

export interface Request {
  id: string;
  kind: string;
  status: "pending" | "applying" | "done" | "rejected";
  result?: Record<string, unknown> | null;
  created_at?: string;
}

export interface ActionDeps {
  enqueue(kind: string, args: Record<string, unknown>): Promise<{ id: string; status: string }>;
  request(id: string): Promise<Request | null>;
  suggestions(limit: number): Promise<Record<string, unknown>[]>;
  ignoreSuggestions(ids: string[] | null, beforeMs: number | null): Promise<number>;
}

const dateField = { type: "string", pattern: "^\\d{4}-\\d{2}-\\d{2}$" };
const amountField = { type: "number", exclusiveMinimum: 0, maximum: 1000000000, description: "Valor em reais, positivo (ex.: 32.90)" };

const baseActions: (ToolDefinition & { destructive?: boolean })[] = [
  {
    name: "add_transaction",
    title: "Lançar despesa ou receita",
    description:
      "Registra uma despesa ou receita numa conta. Use get_accounts e get_categories para os ids. " +
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
      },
      required: ["type", "amount", "description", "account_id", "category_id"],
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
        date: dateField,
        note: { type: "string", maxLength: 200 },
      },
      required: ["from_account_id", "to_account_id", "amount"],
      additionalProperties: false,
    },
  },
  {
    name: "update_transaction",
    title: "Corrigir lançamento",
    description: "Corrige valor, descrição, categoria, conta, data ou observação de um lançamento existente.",
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
    name: "get_request_status",
    title: "Situação de um pedido",
    description: "Diz se um pedido de lançamento, correção ou exclusão já foi gravado pelo Nexo, ainda espera o app abrir, ou foi recusado (com o motivo).",
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
  if (text(c.type) && text(c.type) !== type) {
    throw new ToolInputError(`A categoria ${text(c.name)} é de ${text(c.type) === "income" ? "receita" : "despesa"}.`);
  }
  return c;
}

function editable(l: Ledger, id: string) {
  const tx = l.transactions.find((t) => text(t.id) === id);
  if (!tx) throw new ToolInputError("Lançamento não encontrado. Use list_transactions para ver os ids.");
  const m = meta(metadataIndex(l).get(id));
  if (id.startsWith("investment:") || m.source.startsWith("investment:")) {
    throw new ToolInputError("Movimentações de investimento são alteradas na aba Investir do app.");
  }
  return tx;
}

const pending = (id: string, what: string) => ({
  request_id: id,
  status: "pendente",
  message: `${what} enviado ao Nexo. Ele é gravado quando o app estiver aberto no celular ou no PC; confira com get_request_status.`,
});

const statusText: Record<string, string> = {
  pending: "pendente: aguardando o app do Nexo abrir",
  applying: "em andamento no app",
  done: "gravado no Nexo",
  rejected: "recusado pelo Nexo",
};

export const actions: (ToolDefinition & { destructive?: boolean })[] = [...baseActions, ...moreActions, ...allActions];

/// Server refusals the assistant can act on, instead of a generic failure.
function guarded(deps: ActionDeps): ActionDeps {
  return {
    ...deps,
    enqueue: async (kind, args) => {
      try {
        return await deps.enqueue(kind, args);
      } catch (error) {
        const reason = error instanceof Error ? error.message : "";
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

export async function callAction(name: string, rawArgs: unknown, l: Ledger, today: string,
  rawDeps: ActionDeps): Promise<Record<string, unknown>> {
  const deps = guarded(rawDeps);
  const args = (rawArgs ?? {}) as Args;
  if (typeof args !== "object" || Array.isArray(args)) throw new ToolInputError("Argumentos inválidos.");
  switch (name) {
    case "add_transaction": {
      only(args, ["type", "amount", "description", "account_id", "category_id", "date", "note"]);
      const type = args.type;
      if (type !== "expense" && type !== "income") throw new ToolInputError("type deve ser expense ou income.");
      const a = account(l, str(args, "account_id", 256));
      category(l, str(args, "category_id", 256), type);
      const r = await deps.enqueue("transaction.add", {
        type, amount_cents: amountCents(args), description: str(args, "description", 80),
        account_id: text(a.id), category_id: args.category_id, date: date(args, "date", today, true),
        note: str(args, "note", 200, false) ?? "",
      });
      return pending(r.id, type === "expense" ? "Despesa" : "Receita");
    }
    case "add_transfer": {
      only(args, ["from_account_id", "to_account_id", "amount", "date", "note"]);
      const from = account(l, str(args, "from_account_id", 256));
      const to = account(l, str(args, "to_account_id", 256));
      if (text(from.id) === text(to.id)) throw new ToolInputError("Escolha contas diferentes.");
      const r = await deps.enqueue("transfer.add", {
        from_account_id: text(from.id), to_account_id: text(to.id), amount_cents: amountCents(args),
        date: date(args, "date", today, true), note: str(args, "note", 200, false) ?? "",
      });
      return pending(r.id, "Transferência");
    }
    case "update_transaction": {
      only(args, ["id", "amount", "description", "category_id", "account_id", "date", "note"]);
      const id = str(args, "id", 256)!;
      const tx = editable(l, id);
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
      return {
        suggestions: rows.map((s) => ({
          id: s.id, bank: s.bank, date: new Date(Number(s.occurred_at)).toISOString().slice(0, 10),
          amount: Number(s.amount_cents) / 100, kind: s.kind, medium: s.medium === "credit" ? "cartão" : "conta",
          description: s.description, settled: s.settled, installment: s.installment ?? undefined,
        })),
        note: "Sugestões não são lançamentos. Confirme as que são reais com confirm_suggestion e descarte o resto com ignore_suggestions.",
      };
    }
    case "confirm_suggestion": {
      only(args, ["id", "account_id", "category_id", "type", "description"]);
      const id = str(args, "id", 80)!;
      if (!/^pluggy:[0-9A-Za-z-]{1,64}$/.test(id)) throw new ToolInputError("id de sugestão inválido.");
      const type = args.type;
      if (type !== undefined && type !== "expense" && type !== "income") {
        throw new ToolInputError("type deve ser expense ou income.");
      }
      const a = account(l, str(args, "account_id", 256));
      const c = category(l, str(args, "category_id", 256), typeof type === "string" ? type : text(
        l.categories.find((x) => text(x.id) === args.category_id)?.type));
      const r = await deps.enqueue("suggestion.confirm", {
        id, account_id: text(a.id), category_id: text(c.id), type: type ?? text(c.type),
        description: str(args, "description", 80, false),
      });
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
    case "get_request_status": {
      only(args, ["id"]);
      const id = str(args, "id", 64)!;
      if (!/^[0-9a-f-]{36}$/.test(id)) throw new ToolInputError("id de pedido inválido.");
      const r = await deps.request(id);
      if (!r) throw new ToolInputError("Pedido não encontrado.");
      const waiting = r.status === "pending" || r.status === "applying";
      const minutes = waiting && r.created_at ? Math.max(0, Math.round((Date.now() - Date.parse(r.created_at)) / 60000)) : undefined;
      return {
        request_id: r.id, kind: r.kind, status: statusText[r.status] ?? r.status, result: r.result ?? undefined,
        waiting_minutes: minutes,
        next_step: !waiting ? undefined : r.status === "applying"
          ? "Um aparelho está gravando agora; consulte de novo em alguns segundos."
          : "Será gravado quando o Nexo estiver aberto no celular ou no PC (o PC aberto grava em até 20 s).",
      };
    }
    default: {
      const more = await callMoreAction(name, args, l, today, deps.enqueue) ??
        await callAllAction(name, args, l, today, deps.enqueue);
      if (more) return more;
      throw new ToolInputError("Ferramenta desconhecida.");
    }
  }
}
