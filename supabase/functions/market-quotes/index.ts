// Supabase Edge Function: current price of US stocks and ETFs for the app.
// The caller is identified by their own Supabase session and must be the
// owner; the Finnhub key comes from the function secrets and never reaches
// the app, the response or the logs. The request carries tickers only.
import { quotes, RateLimited, symbols } from "./quotes.ts";
import { backfillUrl, closesFromQuotes, historySymbol, parseAlphaVantage } from "./history.ts";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (request: Request) => Response | Promise<Response>): void;
};
declare const EdgeRuntime: { waitUntil(promise: Promise<unknown>): void } | undefined;

const url = Deno.env.get("SUPABASE_URL")!;

function serviceKey(): string {
  const legacy = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacy) return legacy;
  const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
  const first = Object.values(keys)[0];
  if (!first) throw new Error("service_key_missing");
  return first;
}

async function rpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  const key = serviceKey();
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
  if (!response.ok) throw new Error(`rpc_${response.status}`);
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

/// The chart of [symbol]: the closes the server kept; the first time, and
/// only with the optional Alpha Vantage key, the last ~100 days too.
async function history(symbol: string) {
  type Stored = { points: { day: string; close_micros: number }[]; backfilled: boolean };
  let stored = await rpc("nexo_market_history", { p_symbol: symbol, p_days: 370 }) as Stored;
  const key = Deno.env.get("ALPHAVANTAGE_API_KEY");
  if (key && !stored.backfilled && stored.points.length < 20) {
    try {
      const response = await fetch(backfillUrl(symbol, key), { redirect: "error" });
      if (response.ok) {
        const today = new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York" }).format(new Date());
        const rows = parseAlphaVantage(symbol, await response.json(), today);
        if (rows.length > 0) {
          await rpc("nexo_market_store", { p_rows: rows, p_source: "backfill" });
          stored = await rpc("nexo_market_history", { p_symbol: symbol, p_days: 370 }) as Stored;
        }
      }
    } catch {
      // The kept closes are still an answer.
    }
  }
  return { symbol, currency: "USD", points: stored.points, backfilled: stored.backfilled };
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
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return json(400, { error: "bad_symbols" });
  }
  if (body && typeof body === "object" && "history" in body) {
    let symbol: string;
    try {
      symbol = historySymbol(body);
    } catch {
      return json(400, { error: "bad_symbols" });
    }
    try {
      return json(200, await history(symbol));
    } catch {
      // A server without the 1.17.0 migration.
      return json(503, { error: "history_unavailable" });
    }
  }
  let list: string[];
  try {
    list = symbols(body);
  } catch {
    return json(400, { error: "bad_symbols" });
  }
  try {
    const found = await quotes(list, key, (u) => fetch(u, { redirect: "error" }), Date.now());
    // Each quote is also the day's close, for the chart. Never delays the answer.
    const closes = closesFromQuotes(found);
    if (closes.length > 0) {
      const keep = rpc("nexo_market_store", { p_rows: closes, p_source: "quote" }).catch(() => {});
      if (typeof EdgeRuntime !== "undefined") EdgeRuntime.waitUntil(keep);
    }
    return json(200, { quotes: found });
  } catch (error) {
    if (error instanceof RateLimited) return json(429, { error: "rate_limited" });
    // Only a code: the provider URL carries the key.
    return json(502, { error: "quotes_failed" });
  }
});
