// Minimal MCP server over Streamable HTTP (JSON responses, stateless).
// Read tools answer from the synced ledger; change tools only queue requests
// that the app applies. Authentication and data are injected so the whole
// request path is testable without a network or a database.
import type { Ledger } from "./finance.ts";
import { type ActionDeps, actions, callAction } from "./actions.ts";
import { readOnlyMore } from "./more_actions.ts";
import { readOnlyAll } from "./all_actions.ts";
import { readOnlyParity } from "./parity_actions.ts";
import { callTool, ToolInputError, tools } from "./tools.ts";

export const serverInfo = { name: "nexo", title: "Nexo", version: "0.2.0" };
const supported = ["2025-11-25", "2025-06-18", "2025-03-26"];

export interface Connector {
  id: string;
  ownerId: string;
  datasetId: string;
}

export interface Deps {
  /// Resolves the bearer token (hashed by the caller) to a live connector.
  authenticate(token: string): Promise<Connector | null>;
  load(connector: Connector): Promise<Ledger>;
  audit(connector: Connector, tool: string, ok: boolean): Promise<void>;
  today(): string; // YYYY-MM-DD in the person's time zone
  /// Request queue and suggestions for this connector (absent: read-only).
  actions?(connector: Connector): ActionDeps;
}

export const readOnlyActions = new Set(["list_suggestions", "get_request_status", "get_bank_sync_status", "get_daily_digest",
  ...readOnlyMore, ...readOnlyAll, ...readOnlyParity]);

/// Every change tool accepts a key that makes resending it safe.
const idempotencyKey = {
  type: "string", minLength: 1, maxLength: 120,
  description: "Opcional. Chave única deste pedido: reenviar com a mesma chave não duplica. Sem chave, o mesmo pedido repetido em 10 minutos também não duplica; para dois pedidos iguais de propósito, use chaves diferentes.",
};
const withKey = (schema: Record<string, unknown>) => ({
  ...schema,
  properties: { ...(schema.properties as Record<string, unknown> ?? {}), idempotency_key: idempotencyKey },
});

export const instructions =
  "Dados financeiros pessoais do Nexo. Você pode fazer no Nexo tudo o que a pessoa faz no app; se não souber se algo é possível, " +
  "consulte describe_app_capabilities. Valores vêm da última sincronização do app. Não invente valores: se uma ferramenta não " +
  "trouxer o dado, diga que ele não está disponível. Transferências, reservas/objetivos, pagamentos de fatura, ajustes de saldo e " +
  "aportes não contam como consumo. " +
  "Lançar, corrigir e apagar viram pedidos que o app grava com as próprias regras, um de cada vez e na ordem em que foram feitos: " +
  "só diga que foi feito depois que get_request_status disser 'gravado no Nexo'. Um pedido pode usar o new_id de algo criado num " +
  "pedido anterior ainda pendente. Antes de lançar, confira se já não existe o mesmo lançamento; reenviar o mesmo pedido não " +
  "duplica (idempotency_key). Todo pedido gravado pode ser desfeito com undo_request; list_requests mostra o que foi feito. " +
  "Em mudanças em lote (update_transactions, delete_transactions, convert_to_balance_adjustment, merge_categories) rode antes " +
  "com dry_run e mostre o resultado. Para acertar um saldo com o extrato use adjust_account_balance, nunca uma despesa ou " +
  "receita de ajuste; acertos antigos lançados como receita viram ajuste neutro com convert_to_balance_adjustment. " +
  "Retirar de um objetivo devolve dinheiro à conta; se a reserva era só contábil, use move_goal com move_money false. " +
  "Orçamento por tipo de gasto: get_spending_types, set_category_type e set_spending_targets. Orçamento criado no meio do mês " +
  "fica proporcional, a menos que full_period seja true.";

type Json = Record<string, unknown>;
const rpcError = (id: unknown, code: number, message: string) => ({
  jsonrpc: "2.0", id: id ?? null, error: { code, message },
});

async function dispatch(message: Json, connector: Connector, deps: Deps): Promise<Json | null> {
  const { id, method } = message;
  const params = (message.params ?? {}) as Json;
  if (typeof method !== "string") return rpcError(id, -32600, "Invalid request");
  // Notifications (no id) never get a response.
  if (id === undefined) return null;
  switch (method) {
    case "initialize": {
      const requested = params.protocolVersion;
      return {
        jsonrpc: "2.0", id,
        result: {
          protocolVersion: typeof requested === "string" && supported.includes(requested) ? requested : supported[1],
          capabilities: { tools: { listChanged: false } },
          serverInfo,
          instructions,
        },
      };
    }
    case "ping":
      return { jsonrpc: "2.0", id, result: {} };
    case "tools/list":
      return {
        jsonrpc: "2.0", id,
        result: {
          tools: [
            ...tools.map((t) => ({ ...t, annotations: { readOnlyHint: true, openWorldHint: false } })),
            ...(deps.actions ? actions : []).map(({ destructive, ...t }) => ({
              ...t,
              inputSchema: readOnlyActions.has(t.name) ? t.inputSchema : withKey(t.inputSchema),
              annotations: {
                readOnlyHint: readOnlyActions.has(t.name),
                destructiveHint: destructive === true,
                openWorldHint: false,
              },
            })),
          ],
        },
      };
    case "tools/call": {
      const name = params.name;
      const isAction = deps.actions !== undefined && actions.some((t) => t.name === name);
      if (typeof name !== "string" || (!isAction && !tools.some((t) => t.name === name))) {
        return rpcError(id, -32602, "Unknown tool");
      }
      try {
        const ledger = await deps.load(connector);
        const data = isAction
          ? await callAction(name, params.arguments, ledger, deps.today(), deps.actions!(connector))
          : callTool(name, params.arguments, ledger, deps.today());
        await deps.audit(connector, name, true);
        return {
          jsonrpc: "2.0", id,
          result: { content: [{ type: "text", text: JSON.stringify(data) }], structuredContent: data, isError: false },
        };
      } catch (error) {
        await deps.audit(connector, name, false);
        const text = error instanceof ToolInputError ? error.message : "Não foi possível consultar o Nexo agora.";
        return { jsonrpc: "2.0", id, result: { content: [{ type: "text", text }], isError: true } };
      }
    }
    default:
      return rpcError(id, -32601, "Method not found");
  }
}

const json = (body: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...extra },
  });

export function createHandler(deps: Deps) {
  return async (request: Request): Promise<Response> => {
    if (request.method === "GET" || request.method === "DELETE") {
      // No server-initiated stream or session to end in this stateless server.
      return new Response(null, { status: 405, headers: { Allow: "POST" } });
    }
    if (request.method !== "POST") return new Response(null, { status: 405, headers: { Allow: "POST" } });
    // Claude.ai custom connectors take only a URL, so the token may also be
    // the last path segment (…/nexo-mcp/<token>). The header wins if present.
    const header = request.headers.get("Authorization") ?? "";
    const fromPath = new URL(request.url).pathname.split("/").pop() ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : fromPath;
    const connector = /^nexo_mcp_[A-Za-z0-9]{40,128}$/.test(token) ? await deps.authenticate(token) : null;
    if (!connector) {
      return json(rpcError(null, -32001, "Unauthorized"), 401, { "WWW-Authenticate": 'Bearer realm="nexo"' });
    }
    const length = Number(request.headers.get("Content-Length") ?? "0");
    if (length > 64 * 1024) return json(rpcError(null, -32600, "Request too large"), 413);
    let body: unknown;
    try {
      const raw = await request.text();
      if (raw.length > 64 * 1024) return json(rpcError(null, -32600, "Request too large"), 413);
      body = JSON.parse(raw);
    } catch {
      return json(rpcError(null, -32700, "Parse error"), 400);
    }
    const batch = Array.isArray(body);
    const messages = (batch ? body : [body]) as unknown[];
    if (messages.length === 0 || messages.length > 20 || messages.some((m) => !m || typeof m !== "object")) {
      return json(rpcError(null, -32600, "Invalid request"), 400);
    }
    const replies = [];
    for (const message of messages) {
      const reply = await dispatch(message as Json, connector, deps);
      if (reply) replies.push(reply);
    }
    if (replies.length === 0) return new Response(null, { status: 202 });
    return json(batch ? replies : replies[0]);
  };
}
