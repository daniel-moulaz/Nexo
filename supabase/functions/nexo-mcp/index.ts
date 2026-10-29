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
// Legacy service-role JWT or a new `sb_secret_` key, whichever exists.
const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ||
  Object.values(JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>)[0];
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
      ...(key.startsWith("eyJ") ? { Authorization: `Bearer ${key}` } : {}),
      "Content-Type": "application/json",
    },
    body: JSON.stringify(args),
  });
  if (!response.ok) {
    // PostgREST puts the raised message (e.g. kind_unsupported) in `message`.
    let reason = "";
    try {
      reason = String((JSON.parse(await response.text()) as { message?: unknown }).message ?? "");
    } catch {
      // Not JSON: the status is enough.
    }
    throw new Error(`rpc_${response.status}${reason ? `:${reason.slice(0, 60)}` : ""}`);
  }
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
      devices?: Row[];
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
      budgets: of("budgets"),
      goals: of("savings_goals"),
      contributions: of("savings_contributions"),
      recurringHistory: of("recurring_history"),
      loans: of("loans"),
      loanPayments: of("loan_payments"),
      lended: of("lended_money"),
      lendedPeople: of("lended_people"),
      assets: of("assets"),
      wishlist: of("wishlist"),
      invoicePayments: of("card_invoice_payments"),
      importRules: of("import_rules"),
      sharedSettings: of("shared_settings"),
      devices: data.devices ?? [],
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
  actions(c: Connector) {
    return {
      enqueue: async (kind, args, key) => {
        try {
          return await rpc("nexo_mcp_enqueue_v2", { p_connector_id: c.id, p_kind: kind, p_args: args, p_key: key ?? null }) as
            { id: string; status: string; deduplicated?: boolean };
        } catch (error) {
          // Before the parity migration: the older queue, without keys.
          if (!(error instanceof Error) || !error.message.startsWith("rpc_404")) throw error;
          return await rpc("nexo_mcp_enqueue", { p_connector_id: c.id, p_kind: kind, p_args: args }) as { id: string; status: string };
        }
      },
      recent: async (limit) => await rpc("nexo_mcp_recent", { p_connector_id: c.id, p_limit: limit }) as Record<string, unknown>[],
      bankAccounts: async () => await rpc("nexo_mcp_bank_accounts", { p_connector_id: c.id }) as Record<string, unknown>[],
      linkBankAccount: async (accountId, nexoAccountId) =>
        await rpc("nexo_mcp_link_bank_account", { p_connector_id: c.id, p_account_id: accountId, p_nexo_account_id: nexoAccountId }) as number,
      request: async (id) => await rpc("nexo_mcp_command", { p_connector_id: c.id, p_id: id }) as never,
      suggestions: async (limit) =>
        await rpc("nexo_mcp_suggestions", { p_connector_id: c.id, p_limit: limit }) as Record<string, unknown>[],
      ignoreSuggestions: async (ids, beforeMs) =>
        await rpc("nexo_mcp_ignore_suggestions", { p_connector_id: c.id, p_ids: ids, p_before_ms: beforeMs }) as number,
      bankStatus: async () => await rpc("nexo_mcp_bank_status", { p_connector_id: c.id }) as Record<string, unknown>[],
    };
  },
});

Deno.serve(handler);
