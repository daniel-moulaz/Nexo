// Supabase Edge Function entry point. Deploy with JWT verification disabled
// (the connector authenticates with its own revocable token, not a Supabase
// session). The service role key is provided by the platform at runtime and
// never leaves the function; queries are always scoped to the connector owner.
import type { Ledger, Row } from "./finance.ts";
import { type Connector, createHandler } from "./mcp.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): void;
};

const url = Deno.env.get("SUPABASE_URL")!;
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const timeZone = Deno.env.get("NEXO_TIME_ZONE") ?? "America/Sao_Paulo";

async function sha256(text: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    redirect: "error",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) throw new Error(`rpc_${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

const handler = createHandler({
  async authenticate(token) {
    const row = await rpc("nexo_mcp_authenticate", { p_token_hash: await sha256(token) }) as Row | null;
    if (!row || typeof row.id !== "string") return null;
    return { id: row.id, ownerId: String(row.owner_id), datasetId: String(row.dataset_id) };
  },
  async load(c: Connector): Promise<Ledger> {
    const data = await rpc("nexo_mcp_ledger", { p_connector_id: c.id }) as {
      entities: { kind: string; value: Row }[];
      balances: { account_id: string; micros: number }[];
    };
    const of = (kind: string) => data.entities.filter((e) => e.kind === kind && e.value).map((e) => e.value);
    return {
      mainCurrency: Deno.env.get("NEXO_MAIN_CURRENCY") ?? "BRL",
      accounts: of("accounts"),
      balances: Object.fromEntries(data.balances.map((b) => [b.account_id, Number(b.micros)])),
      categories: of("categories"),
      transactions: of("transactions"),
      metadata: of("transaction_metadata"),
      recurring: of("recurring_payments"),
      investments: of("investments"),
      investmentOperations: of("investment_operations"),
    };
  },
  async audit(c, tool, ok) {
    try {
      await rpc("nexo_mcp_audit", { p_connector_id: c.id, p_tool: tool, p_ok: ok });
    } catch {
      // Auditing must not turn a correct answer into a failure.
    }
  },
  today() {
    return new Intl.DateTimeFormat("en-CA", { timeZone }).format(new Date());
  },
});

Deno.serve(handler);
