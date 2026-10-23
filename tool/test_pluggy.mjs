// Tests for the Pluggy client and normalizer: `node tool/test_pluggy.mjs`.
// Synthetic objects shaped by api.pluggy.ai/oas3.json; no network, no keys.
import assert from 'node:assert/strict';
import { bankUpdatedAt, isSkip, itemHealth, merge, toAccountSnapshot, toSuggestion } from '../supabase/functions/pluggy-sync/normalize.ts';
import { PluggyClient, PluggyError } from '../supabase/functions/pluggy-sync/pluggy.ts';

let passed = 0;
async function test(name, action) {
  await action();
  passed++;
  console.log(`PASS ${name}`);
}

const bank = { id: 'acc-bank', type: 'BANK', subtype: 'CHECKING_ACCOUNT', name: 'Conta fictícia', currencyCode: 'BRL', itemId: 'item-1' };
const card = { id: 'acc-card', type: 'CREDIT', subtype: 'CREDIT_CARD', name: 'Cartão fictício', currencyCode: 'BRL', itemId: 'item-1' };
const tx = (over = {}) => ({
  id: 'tx-1', description: 'Mercado Fictício', currencyCode: 'BRL', amount: -32.9,
  date: '2026-10-19T15:30:00.000Z', type: 'DEBIT', status: 'POSTED', category: 'Groceries',
  accountId: 'acc-bank', updatedAt: '2026-10-19T16:00:00.000Z', ...over,
});

await test('debit becomes an expense suggestion keyed by the Pluggy id', () => {
  const s = toSuggestion(tx(), bank);
  assert.equal(isSkip(s), false);
  assert.equal(s.external_id, 'pluggy:tx-1');
  assert.equal(s.amount_cents, 3290);
  assert.equal(s.kind, 'expense');
  assert.equal(s.medium, 'bank');
  assert.equal(s.settled, true);
});

await test('direction comes from type, never from the amount sign', () => {
  assert.equal(toSuggestion(tx({ amount: 32.9 }), bank).kind, 'expense');
  assert.equal(toSuggestion(tx({ type: 'CREDIT', amount: -5000, description: 'Salário' }), bank).kind, 'income');
});

await test('card purchase, refund, bill payment and installments', () => {
  const purchase = toSuggestion(tx({ accountId: 'acc-card', creditCardMetadata: { installmentNumber: 2, totalInstallments: 6 } }), card);
  assert.equal(purchase.kind, 'expense');
  assert.equal(purchase.medium, 'credit');
  assert.equal(purchase.installment, '2/6');
  assert.equal(toSuggestion(tx({ accountId: 'acc-card', type: 'CREDIT', description: 'Estorno loja' }), card).kind, 'refund');
  assert.equal(toSuggestion(tx({ accountId: 'acc-card', type: 'CREDIT', description: 'Pagamento de fatura' }), card).kind, 'transfer');
});

await test('only clear own-account moves become transfers', () => {
  assert.equal(toSuggestion(tx({ description: 'Transferência entre contas' }), bank).kind, 'transfer');
  assert.equal(toSuggestion(tx({ description: 'Aplicação CDB' }), bank).kind, 'transfer');
  assert.equal(toSuggestion(tx({ description: 'Resgate poupança', type: 'CREDIT' }), bank).kind, 'transfer');
  // A Pix to a store or a salary by TED must not disappear from reports.
  assert.equal(toSuggestion(tx({ description: 'Pix enviado Padaria', operationType: 'PIX' }), bank).kind, 'expense');
  assert.equal(toSuggestion(tx({ description: 'TED recebida Empresa', type: 'CREDIT', operationType: 'TED' }), bank).kind, 'income');
});

await test('pending stays marked unsettled', () => {
  assert.equal(toSuggestion(tx({ status: 'PENDING' }), bank).settled, false);
});

await test('foreign currency uses account amount or is skipped', () => {
  const converted = toSuggestion(tx({ currencyCode: 'USD', amount: -10, amountInAccountCurrency: -54.37 }), bank);
  assert.equal(converted.amount_cents, 5437);
  assert.equal(toSuggestion(tx({ currencyCode: 'USD', amount: -10 }), bank).reason, 'unsupported_currency');
  assert.equal(toSuggestion(tx(), { ...bank, currencyCode: 'USD' }).reason, 'unsupported_currency');
});

await test('invalid, zero or mismatched rows are skipped, not guessed', () => {
  assert.equal(toSuggestion(tx({ amount: 0 }), bank).reason, 'zero');
  assert.equal(toSuggestion(tx({ date: 'ontem' }), bank).reason, 'invalid');
  assert.equal(toSuggestion(tx({ type: 'OTHER' }), bank).reason, 'invalid');
  assert.equal(toSuggestion(tx({ accountId: 'acc-card' }), bank).reason, 'invalid');
  assert.equal(toSuggestion(tx({ amount: NaN }), bank).reason, 'invalid');
});

await test('refreshes update pending suggestions; decisions are never rewritten', () => {
  const first = toSuggestion(tx(), bank);
  assert.equal(merge(undefined, first).action, 'insert');
  const corrected = toSuggestion(tx({ amount: -35, updatedAt: '2026-10-20T10:00:00.000Z' }), bank);
  assert.equal(merge({ ...first, review: 'pending' }, corrected).action, 'update');
  assert.equal(merge({ ...first, review: 'confirmed' }, corrected).action, 'flag_changed');
  const cosmetic = toSuggestion(tx({ description: 'MERCADO FICTICIO LTDA', updatedAt: '2026-10-20T10:00:00.000Z' }), bank);
  assert.equal(merge({ ...first, review: 'ignored' }, cosmetic).action, 'keep');
  assert.equal(merge({ ...corrected, review: 'pending' }, first).action, 'keep', 'older data never wins');
});

await test('item health: expired consent, errors and early warning', () => {
  const now = new Date('2026-10-20T12:00:00Z');
  assert.equal(itemHealth({ status: 'LOGIN_ERROR', error: { code: 'USER_AUTHORIZATION_EXPIRED' } }, now).state, 'reconnect');
  assert.equal(itemHealth({ status: 'UPDATED', consentExpiresAt: '2026-10-30T00:00:00Z' }, now).state, 'expiring');
  assert.equal(itemHealth({ status: 'UPDATED', consentExpiresAt: '2027-10-01T00:00:00Z' }, now).state, 'ok');
  assert.equal(itemHealth({ status: 'OUTDATED' }, now).state, 'error');
});

// ── Client ───────────────────────────────────────────────────────────────
function fakeApi(handler) {
  const calls = [];
  const fetcher = async (url, init = {}) => {
    calls.push({ url, init });
    return handler(url, init, calls);
  };
  return { calls, fetcher };
}
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

await test('authenticates once and sends the key only to Pluggy', async () => {
  const api = fakeApi((url) => url.endsWith('/auth') ? json({ apiKey: 'k1' }) : json({ results: [bank] }));
  const client = new PluggyClient('id', 'secret', api.fetcher, 'https://api.example');
  await client.accounts('item-1');
  await client.accounts('item-1');
  assert.equal(api.calls.filter(c => c.url.endsWith('/auth')).length, 1);
  assert.equal(api.calls[1].init.headers['X-API-KEY'], 'k1');
  assert.equal(api.calls[1].url, 'https://api.example/accounts?itemId=item-1');
  assert(api.calls.every(c => c.init.redirect === 'error'));
});

await test('expired key re-authenticates once, then fails clearly', async () => {
  let keys = 0;
  const api = fakeApi((url, init) => {
    if (url.endsWith('/auth')) return json({ apiKey: `k${++keys}` });
    return init.headers['X-API-KEY'] === 'k1' ? new Response('', { status: 401 }) : json({ results: [] });
  });
  const client = new PluggyClient('id', 'secret', api.fetcher, 'https://api.example');
  assert.deepEqual(await client.accounts('item-1'), []);
  assert.equal(keys, 2);
  const denied = new PluggyClient('id', 'bad', fakeApi(() => new Response('', { status: 401 })).fetcher, 'https://api.example');
  await assert.rejects(denied.accounts('item-1'), e => e instanceof PluggyError && e.status === 401 && !e.retryable);
});

await test('transactions follow the v2 cursor until next is null', async () => {
  const pages = {
    '?accountId=acc-bank&dateFrom=2026-09-20': { results: [tx({ id: 'a' })], next: '?accountId=acc-bank&after=c1' },
    '?accountId=acc-bank&after=c1': { results: [tx({ id: 'b' })], next: null },
  };
  const api = fakeApi((url) => url.endsWith('/auth') ? json({ apiKey: 'k' })
    : json(pages[url.slice(url.indexOf('?'))]));
  const client = new PluggyClient('id', 'secret', api.fetcher, 'https://api.example');
  const all = await client.transactions('acc-bank', '2026-09-20');
  assert.deepEqual(all.map(t => t.id), ['a', 'b']);
  assert(api.calls.slice(1).every(c => c.url.startsWith('https://api.example/v2/transactions?')));
});

await test('rate limit is retryable; malformed cursor is refused', async () => {
  const limited = new PluggyClient('id', 's', fakeApi((url) => url.endsWith('/auth') ? json({ apiKey: 'k' }) : new Response('', { status: 429 })).fetcher, 'https://api.example');
  await assert.rejects(limited.transactions('acc-bank', '2026-10-01'), e => e.retryable === true);
  const evil = new PluggyClient('id', 's', fakeApi((url) => url.endsWith('/auth') ? json({ apiKey: 'k' })
    : json({ results: [], next: 'https://attacker.example/steal' })).fetcher, 'https://api.example');
  await assert.rejects(evil.transactions('acc-bank', '2026-10-01'), e => e instanceof PluggyError);
});

// ── syncOwner: one refresh with fake Pluggy and fake store ─────────────
const { syncOwner } = await import('../supabase/functions/pluggy-sync/sync.ts');
function fakeStore(items) {
  const rows = new Map();
  const healths = [];
  return {
    rows, healths,
    items: async () => items,
    stored: async (_o, ids) => ids.filter(id => rows.has(id)).map(id => rows.get(id)),
    store: async (_o, itemId, health, incoming) => {
      healths.push([itemId, health.state]);
      let n = 0;
      for (const r of incoming) {
        const old = rows.get(r.external_id);
        if (r.action === 'insert' && !old) { rows.set(r.external_id, { ...r, review: 'pending' }); n++; }
        if (r.action === 'update' && old?.review === 'pending') { rows.set(r.external_id, { ...r, review: 'pending' }); n++; }
        if (r.action === 'flag_changed' && old && old.review !== 'pending') { old.changed = true; old.source_updated_at = r.source_updated_at; n++; }
      }
      return n;
    },
  };
}
const source = (txs, item = { status: 'UPDATED' }) => ({
  item: async () => item,
  accounts: async () => [bank],
  transactions: async () => txs,
});
const now = new Date('2026-10-20T12:00:00.000Z');

await test('sync: new transactions become pending suggestions, skips counted', async () => {
  const store = fakeStore([{ item_id: 'item-1', label: 'Banco', last_fetch_at: null }]);
  const [r] = await syncOwner('owner', source([tx({ id: 'a' }), tx({ id: 'b', amount: 0 })]), store, { now });
  assert.equal(r.fetched, true);
  assert.equal(r.written, 1);
  assert.equal(r.skipped, 1);
  assert.equal(store.rows.get('pluggy:a').review, 'pending');
  assert.deepEqual(store.healths, [['item-1', 'ok']]);
});

await test('sync: refresh updates pending and flags a decided change', async () => {
  const store = fakeStore([{ item_id: 'item-1', label: 'Banco', last_fetch_at: null }]);
  await syncOwner('owner', source([tx({ id: 'a' }), tx({ id: 'b' })]), store, { now });
  store.rows.get('pluggy:a').review = 'confirmed';
  const later = { updatedAt: '2026-10-20T10:00:00.000Z', amount: -40 };
  await syncOwner('owner', source([tx({ id: 'a', ...later }), tx({ id: 'b', ...later })]), store,
    { now: new Date(now.getTime() + 2 * 3600000) });
  assert.equal(store.rows.get('pluggy:a').amount_cents, 3290, 'decision kept');
  assert.equal(store.rows.get('pluggy:a').changed, true);
  assert.equal(store.rows.get('pluggy:b').amount_cents, 4000);
});

await test('sync: reads at most hourly unless forced, and forced waits 5 minutes', async () => {
  const recent = new Date(now.getTime() - 10 * 60000).toISOString();
  const store = fakeStore([{ item_id: 'item-1', label: 'Banco', last_fetch_at: recent }]);
  let reads = 0;
  const counting = { ...source([tx()]), item: async () => { reads++; return { status: 'UPDATED' }; } };
  assert.equal((await syncOwner('owner', counting, store, { now }))[0].fetched, false);
  assert.equal((await syncOwner('owner', counting, store, { now, force: true }))[0].fetched, true);
  assert.equal(reads, 1);
  const veryRecent = fakeStore([{ item_id: 'item-1', label: 'Banco', last_fetch_at: new Date(now.getTime() - 60000).toISOString() }]);
  assert.equal((await syncOwner('owner', counting, veryRecent, { now, force: true }))[0].fetched, false);
});

await test('sync: a Pluggy failure marks the item and keeps stored data', async () => {
  const store = fakeStore([{ item_id: 'item-1', label: 'Banco', last_fetch_at: null }]);
  const failing = { ...source([]), accounts: async () => { throw new PluggyError(404, false); } };
  const [r] = await syncOwner('owner', failing, store, { now });
  assert.equal(r.fetched, false);
  assert.equal(r.health.state, 'reconnect');
  assert.deepEqual(store.healths, [['item-1', 'reconnect']]);
  const expired = source([], { status: 'LOGIN_ERROR', error: { code: 'USER_AUTHORIZATION_EXPIRED' } });
  assert.equal((await syncOwner('owner', expired, fakeStore([{ item_id: 'i', label: 'B', last_fetch_at: null }]), { now }))[0].health.state, 'reconnect');
});

await test('account snapshot: balance and card limits, never number, owner or CPF', () => {
  const snap = toAccountSnapshot({ ...card, number: '1234', owner: 'Pessoa Fictícia', taxNumber: '000.000.000-00',
    balance: 213.59, marketingName: 'Cartão Roxo', creditData: { creditLimit: 650, availableCreditLimit: 15.49,
      minimumPayment: 57.29, balanceCloseDate: '2026-11-19', balanceDueDate: '2026-11-26T00:00:00Z' } });
  assert.deepEqual(snap, { account_id: 'acc-card', type: 'CREDIT', subtype: 'CREDIT_CARD', name: 'Cartão Roxo',
    currency: 'BRL', balance_cents: 21359, credit_limit_cents: 65000, available_cents: 1549,
    minimum_payment_cents: 5729, close_date: '2026-11-19', due_date: '2026-11-26' });
  assert.equal(JSON.stringify(snap).includes('Fictícia'), false);
  const b = toAccountSnapshot({ ...bank, balance: -33 });
  assert.equal(b.balance_cents, -3300);
  assert.equal(b.credit_limit_cents, null);
  assert.equal(toAccountSnapshot({ ...bank, balance: Infinity }).balance_cents, null);
  assert.equal(bankUpdatedAt({ lastUpdatedAt: '2026-10-22T06:00:00.000Z' }), '2026-10-22T06:00:00.000Z');
  assert.equal(bankUpdatedAt({ lastUpdatedAt: 'ontem' }), null);
});

await test('sync: stores balances and the bank time with each read', async () => {
  const store = fakeStore([{ item_id: 'item-1', label: 'Banco', last_fetch_at: null }]);
  const saved = [];
  store.accounts = async (_o, itemId, updatedAt, rows) => saved.push([itemId, updatedAt, rows.map(r => r.account_id)]);
  await syncOwner('owner', source([], { status: 'UPDATED', lastUpdatedAt: '2026-10-20T06:00:00.000Z' }), store, { now });
  assert.deepEqual(saved, [['item-1', '2026-10-20T06:00:00.000Z', ['acc-bank']]]);
});

console.log(`PLUGGY: ${passed} tests passed; synthetic data only.`);
