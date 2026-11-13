// Tests for the market-quotes Edge Function logic, run with Node 24 (native
// type stripping): `node tool/test_market_quotes.mjs`. No network.
import assert from 'node:assert/strict';
import { clearCache, parse, quotes, RateLimited, symbols } from '../supabase/functions/market-quotes/quotes.ts';
import { closesFromQuotes, historySymbol, marketDay, parseAlphaVantage } from '../supabase/functions/market-quotes/history.ts';

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

await test('each quote is the close of its market day (New York date)', () => {
  // 23:30 in Brasília on the 13th is still the 13th in New York; 01:00 UTC is the day before there.
  assert.equal(marketDay('2026-11-14T01:00:00.000Z'), '2026-11-13');
  assert.equal(marketDay('2026-11-13T15:00:00.000Z'), '2026-11-13');
  assert.equal(marketDay('nada'), null);
  assert.deepEqual(closesFromQuotes([{ symbol: 'NVDA', price: 142.5, currency: 'USD', time: '2026-11-13T20:59:00.000Z' }]),
    [{ symbol: 'NVDA', day: '2026-11-13', close_micros: 142500000 }]);
});
await test('history asks for one plain ticker', () => {
  assert.equal(historySymbol({ history: 'NVDA' }), 'NVDA');
  for (const bad of [{}, { history: 'nvda' }, { history: ['NVDA'] }, { history: 'A B' }]) {
    assert.throws(() => historySymbol(bad));
  }
});
await test('the optional first fill keeps sane closes only, oldest first', () => {
  const data = { 'Time Series (Daily)': {
    '2026-11-12': { '4. close': '140.10' },
    '2026-11-11': { '4. close': '138.00' },
    '2026-11-20': { '4. close': '150.00' },
    '2026-11-10': { '4. close': '-1' },
    'ontem': { '4. close': '1' },
  } };
  assert.deepEqual(parseAlphaVantage('NVDA', data, '2026-11-13').map((r) => [r.day, r.close_micros]),
    [['2026-11-11', 138000000], ['2026-11-12', 140100000]]);
  assert.deepEqual(parseAlphaVantage('NVDA', { Note: 'limite' }, '2026-11-13'), [], 'rate-limit note: nothing');
});
console.log(`\n${passed} passed`);
