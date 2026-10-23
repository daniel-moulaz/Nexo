// Supabase Edge Function: refreshes the caller's Pluggy suggestions.
// The caller is identified by their own Supabase session; only the person
// configured in NEXO_PLUGGY_OWNER may use the Pluggy credentials, which come
// from function secrets and never reach the app, the response or logs.
import { PluggyClient } from "./pluggy.ts";
import { type Store, syncOwner } from "./sync.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): void;
};

const url = Deno.env.get("SUPABASE_URL")!;

/// Legacy service-role JWT or a new `sb_secret_` key, whichever the
/// platform provides.
function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
  const first = Object.values(keys)[0];
  if (!first) throw new Error("service_key_missing");
  return first;
}

function headers(key: string): Record<string, string> {
  return {
    apikey: key,
    ...(key.startsWith("eyJ") ? { Authorization: `Bearer ${key}` } : {}),
    "Content-Type": "application/json",
  };
}

async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
    method: "POST",
    redirect: "error",
    headers: headers(serviceKey()),
    body: JSON.stringify(args),
  });
  if (!response.ok) throw new Error(`rpc_${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

const store: Store = {
  items: async (owner) => await rpc("nexo_pluggy_owner_items", { p_owner: owner }) as never,
  stored: async (owner, ids) => await rpc("nexo_pluggy_stored", { p_owner: owner, p_ids: ids }) as never,
  store: async (owner, itemId, health, rows) =>
    await rpc("nexo_pluggy_store", { p_owner: owner, p_item_id: itemId, p_health: health, p_rows: rows }) as number,
  accounts: async (owner, itemId, updatedAt, rows) => {
    try {
      await rpc("nexo_pluggy_store_accounts",
        { p_owner: owner, p_item_id: itemId, p_bank_updated_at: updatedAt, p_accounts: rows });
    } catch {
      // Balances are an extra: a server without the migration keeps working.
    }
  },
};

/// Validates the session with Supabase Auth instead of trusting the token.
async function caller(request: Request): Promise<string | null> {
  const auth = request.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return null;
  const response = await fetch(`${url}/auth/v1/user`, {
    redirect: "error",
    headers: { apikey: serviceKey(), Authorization: auth },
  });
  if (!response.ok) return null;
  const user = await response.json() as { id?: unknown };
  return typeof user.id === "string" ? user.id : null;
}

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const owner = await caller(request);
  if (!owner) return json(401, { error: "authentication_required" });
  if (owner !== Deno.env.get("NEXO_PLUGGY_OWNER")) return json(403, { error: "not_owner" });
  const clientId = Deno.env.get("PLUGGY_CLIENT_ID"), clientSecret = Deno.env.get("PLUGGY_CLIENT_SECRET");
  if (!clientId || !clientSecret) return json(503, { error: "not_configured" });
  let force = false;
  try {
    force = (await request.json() as { force?: unknown }).force === true;
  } catch {
    // An empty body is a normal refresh.
  }
  try {
    const items = await syncOwner(owner, new PluggyClient(clientId, clientSecret), store, { force });
    return json(200, { items });
  } catch (error) {
    // Only a code, never Pluggy or database text.
    return json(502, { error: error instanceof Error && /^[a-z_0-9]+$/.test(error.message) ? error.message : "sync_failed" });
  }
});
