// Minimal MCP server over Streamable HTTP (JSON responses, stateless).
// Read-only tools; authentication and data loading are injected so the whole
// request path is testable without a network or a database.
import type { Ledger } from "./finance.ts";
import { callTool, ToolInputError, tools } from "./tools.ts";

export const serverInfo = { name: "nexo", title: "Nexo", version: "0.1.0" };
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
}

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
          instructions:
            "Dados financeiros pessoais do Nexo, somente leitura. Valores vêm da última sincronização do app. " +
            "Transferências, reservas e pagamentos de fatura não contam como consumo. Não invente valores: " +
            "se uma ferramenta não trouxer o dado, diga que ele não está disponível.",
        },
      };
    }
    case "ping":
      return { jsonrpc: "2.0", id, result: {} };
    case "tools/list":
      return {
        jsonrpc: "2.0", id,
        result: {
          tools: tools.map((t) => ({ ...t, annotations: { readOnlyHint: true, openWorldHint: false } })),
        },
      };
    case "tools/call": {
      const name = params.name;
      if (typeof name !== "string" || !tools.some((t) => t.name === name)) {
        return rpcError(id, -32602, "Unknown tool");
      }
      try {
        const ledger = await deps.load(connector);
        const data = callTool(name, params.arguments, ledger, deps.today());
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
    const header = request.headers.get("Authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
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
