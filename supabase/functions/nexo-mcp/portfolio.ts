// One position in two currencies, the same rule as the app
// (lib/investments/investment_models.dart): money fields are in reais, the
// `native` ones in the asset currency; a foreign operation carries what it
// cost in reais on its own day (brl_cents).
import { num, type Row, text } from "./finance.ts";

export const FX_SCALE = 1_000_000;

/// round(a * b / d) in integers, as the app does.
export function ratio(a: number, b: number, d: number): number {
  const n = BigInt(Math.round(a)) * BigInt(Math.round(b));
  const div = BigInt(Math.round(d));
  const half = div / 2n;
  return Number(n >= 0n ? (n + half) / div : -((-n + half) / div));
}

export const countryOf = (currency: string) => (currency === "USD" ? "EUA" : "Brasil");

export type Position = {
  currency: string;
  quantity: number; // micros
  nativeCost: number; cost: number; // cents
  nativeValue: number; value: number;
  realized: number; income: number; nativeIncome: number; nativeTax: number;
  priceEffect: number; fxEffect: number;
  fxMicros: number;
};

const sortOps = (a: Row, b: Row) =>
  text(a.date).localeCompare(text(b.date)) || text(a.created_at).localeCompare(text(b.created_at)) ||
  text(a.id).localeCompare(text(b.id));

export function position(inv: Row, all: Row[]): Position {
  const currency = text(inv.currency) || "BRL";
  const foreign = currency !== "BRL";
  const fxMicros = foreign ? num(inv.fx_micros) || FX_SCALE : FX_SCALE;
  const ops = all.filter((o) => o.investment_id === inv.id).sort(sortOps);
  let quantity = 0, nativeCost = 0, cost = 0, realized = 0, income = 0, nativeIncome = 0, nativeTax = 0;
  for (const o of ops) {
    const q = num(o.quantity), c = num(o.cents);
    const main = o.brl_cents === null || o.brl_cents === undefined ? c : num(o.brl_cents);
    if (o.kind === "buy" || o.kind === "opening") {
      quantity += q; nativeCost += c; cost += main;
    } else if (o.kind === "sell") {
      if (quantity <= 0) continue;
      const removedNative = ratio(nativeCost, q, quantity), removed = ratio(cost, q, quantity);
      nativeCost -= removedNative; cost -= removed; quantity -= q;
      realized += main - removed;
    } else if (o.kind === "income") {
      nativeIncome += c; nativeTax += num(o.tax_cents); income += main;
    }
  }
  const nativeValue = ratio(quantity, num(inv.price_micros), 10_000_000_000);
  const value = foreign ? ratio(nativeValue, fxMicros, FX_SCALE) : nativeValue;
  const priceEffect = foreign ? ratio(nativeValue - nativeCost, fxMicros, FX_SCALE) : value - cost;
  return {
    currency, quantity, nativeCost, cost, nativeValue, value, realized, income, nativeIncome, nativeTax,
    priceEffect, fxEffect: value - cost - priceEffect, fxMicros,
  };
}

/// Reais per unit of [currency] the app last saved with a price, from the
/// most recently priced asset in it. Null when no asset uses it.
export function lastRate(investments: Row[], currency: string): number | null {
  const priced = investments
    .filter((i) => (text(i.currency) || "BRL") === currency && num(i.fx_micros) > 0)
    .sort((a, b) => text(b.price_at).localeCompare(text(a.price_at)));
  return priced.length ? num(priced[0].fx_micros) : null;
}
