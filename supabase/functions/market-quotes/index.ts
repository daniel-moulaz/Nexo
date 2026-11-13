// Supabase Edge Function: current price of US stocks and ETFs for the app.
// The caller is identified by their own Supabase session and must be the
// owner; the Finnhub key comes from the function secrets and never reaches
// the app, the response or the logs. The request carries tickers only.
import { quotes, RateLimited, symbols } from "./quotes.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): void;
};

const url = Deno.env.get("SUPABASE_URL")!;

function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
  const first = Object.values(keys)[0];
  if (!first) throw new Error("service_key_missing");
  return first;
}

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
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

Deno.serve(async (request) => {
  if (request.method !== "POST") return json(405, { error: "method_not_allowed" });
  const owner = await caller(request);
  if (!owner) return json(401, { error: "authentication_required" });
  const allowed = Deno.env.get("NEXO_QUOTES_OWNER") ?? Deno.env.get("NEXO_PLUGGY_OWNER");
  if (!allowed || owner !== allowed) return json(403, { error: "not_owner" });
  const key = Deno.env.get("FINNHUB_API_KEY");
  if (!key) return json(503, { error: "not_configured" });
  let list: string[];
  try {
    list = symbols(await request.json());
  } catch {
    return json(400, { error: "bad_symbols" });
  }
  try {
    const found = await quotes(list, key, (u) => fetch(u, { redirect: "error" }), Date.now());
    return json(200, { quotes: found });
  } catch (error) {
    if (error instanceof RateLimited) return json(429, { error: "rate_limited" });
    // Only a code: the provider URL carries the key.
    return json(502, { error: "quotes_failed" });
  }
});
