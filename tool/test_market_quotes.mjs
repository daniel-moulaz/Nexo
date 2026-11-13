// Tests for the market-quotes Edge Function logic, run with Node 24 (native
// type stripping): `node tool/test_market_quotes.mjs`. No network.
import assert from 'node:assert/strict';
import { clearCache, parse, quotes, RateLimited, symbols } from '../supabase/functions/market-quotes/quotes.ts';

let passed = 0;
async function test(name, action) {
  clearCache();
  await action();
  passed++;
  console.log(`PASS ${name}`);
}

const now = Date.parse('2026-11-13T15:00:00Z');
const t = now / 1000 - 60;

await test('only short lists of plain tickers', () => {
  assert.deepEqual(symbols({ symbols: ['NVDA', 'NVDA', 'BRK.B', 'F'] }), ['NVDA', 'BRK.B', 'F']);
  for (const bad of [{}, { symbols: [] }, { symbols: ['nvda'] }, { symbols: ['NV DA'] }, { symbols: [1] },
    { symbols: Array.from({ length: 21 }, (_, i) => `A${i}`) }]) {
    assert.throws(() => symbols(bad), /bad_symbols/);
  }
});

await test('a real price becomes a dollar quote with its time', () => {
  const q = parse('NVDA', { c: 166.19, t }, now);
  assert.deepEqual(q, { symbol: 'NVDA', price: 166.19, currency: 'USD', time: new Date(t * 1000).toISOString() });
});

await test('an unknown ticker (price zero) or a future time is dropped', () => {
  assert.equal(parse('XXXX', { c: 0, d: null, t: 0 }, now), null);
  assert.equal(parse('NVDA', { c: 10, t: now / 1000 + 3600 }, now), null);
  assert.equal(parse('NVDA', 'nope', now), null);
  assert.equal(parse('NVDA', { c: Number.NaN, t }, now), null);
});

await test('the key goes only to the provider, and a minute of cache saves calls', async () => {
  const urls = [];
  const fetcher = async (u) => { urls.push(u); return { status: 200, json: async () => ({ c: 100, t }) }; };
  const first = await quotes(['NVDA', 'AAPL'], 'k3y', fetcher, now);
  assert.equal(first.length, 2);
  assert.ok(urls.every((u) => u.startsWith('https://finnhub.io/api/v1/quote?symbol=') && u.endsWith('&token=k3y')));
  await quotes(['NVDA'], 'k3y', fetcher, now + 30_000);
  assert.equal(urls.length, 2, 'served from cache');
  await quotes(['NVDA'], 'k3y', fetcher, now + 61_000);
  assert.equal(urls.length, 3, 'cache expired');
});

await test('a missing ticker is left out, the rest still answers', async () => {
  const fetcher = async (u) => ({ status: 200, json: async () => (u.includes('XXXX') ? { c: 0, t: 0 } : { c: 5, t }) });
  const r = await quotes(['XXXX', 'NVDA'], 'k', fetcher, now);
  assert.deepEqual(r.map((q) => q.symbol), ['NVDA']);
});

await test('the provider limit is reported as such', async () => {
  const fetcher = async () => ({ status: 429, json: async () => ({}) });
  await assert.rejects(quotes(['NVDA'], 'k', fetcher, now), RateLimited);
});

console.log(`\n${passed} passed`);
