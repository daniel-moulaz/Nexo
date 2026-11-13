// Daily closes of US stocks, kept by the Nexo server itself.
//
// Finnhub's free plan has no history. Every quote the app asks for is also
// stored as that market day's close (the last price seen that day wins), so
// the chart grows by itself from the first day the asset is followed. With
// the optional ALPHAVANTAGE_API_KEY secret (free plan: 25 calls a day), the
// first chart of a ticker is filled with its last ~100 trading days, once.

import type { Quote } from "./quotes.ts";

export type Close = { symbol: string; day: string; close_micros: number };

const TICKER = /^[A-Z0-9][A-Z0-9.\-]{0,11}$/;
const DAY = /^\d{4}-\d{2}-\d{2}$/;

/// The New York date of a trade time: the market day it belongs to.
export function marketDay(iso: string): string | null {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return new Intl.DateTimeFormat("en-CA", { timeZone: "America/New_York" }).format(d);
}

export const micros = (price: number) => Math.round(price * 1_000_000);

export function closesFromQuotes(list: Quote[]): Close[] {
  const out: Close[] = [];
  for (const q of list) {
    const day = marketDay(q.time);
    if (day && TICKER.test(q.symbol) && q.price > 0) out.push({ symbol: q.symbol, day, close_micros: micros(q.price) });
  }
  return out;
}

/// `{ "history": "NVDA" }` → the ticker, or an error.
export function historySymbol(body: unknown): string {
  const s = body && typeof body === "object" ? (body as { history?: unknown }).history : undefined;
  if (typeof s !== "string" || !TICKER.test(s)) throw new Error("bad_symbols");
  return s;
}

/// Alpha Vantage TIME_SERIES_DAILY (compact): closes as given (not adjusted
/// for splits, which the free plan does not offer). Anything odd is dropped.
export function parseAlphaVantage(symbol: string, data: unknown, todayIso: string): Close[] {
  if (!data || typeof data !== "object") return [];
  const series = (data as Record<string, unknown>)["Time Series (Daily)"];
  if (!series || typeof series !== "object") return [];
  const out: Close[] = [];
  for (const [day, row] of Object.entries(series as Record<string, unknown>)) {
    if (!DAY.test(day) || day > todayIso || !row || typeof row !== "object") continue;
    const close = Number((row as Record<string, unknown>)["4. close"]);
    if (!Number.isFinite(close) || close <= 0 || close > 1_000_000) continue;
    out.push({ symbol, day, close_micros: micros(close) });
  }
  return out.sort((a, b) => a.day.localeCompare(b.day)).slice(-120);
}

export const backfillUrl = (symbol: string, key: string) =>
  `https://www.alphavantage.co/query?function=TIME_SERIES_DAILY&outputsize=compact&symbol=${encodeURIComponent(symbol)}&apikey=${encodeURIComponent(key)}`;
