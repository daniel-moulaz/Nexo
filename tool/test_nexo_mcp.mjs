// Tests for the nexo-mcp Edge Function logic, run with Node 24 (native type
// stripping): `node tool/test_nexo_mcp.mjs`. Synthetic fixture only; no
// network, no Supabase project.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { analyze, monthFilter, previousMonth } from '../supabase/functions/nexo-mcp/finance.ts';
import { callTool, ToolInputError, tools } from '../supabase/functions/nexo-mcp/tools.ts';
import { createHandler } from '../supabase/functions/nexo-mcp/mcp.ts';

const fixture = JSON.parse(await readFile(new URL('../test/fixtures/mcp_parity.json', import.meta.url), 'utf8'));
const ledger = fixture.ledger;
const today = fixture.today;
let passed = 0;
async function test(name, action) {
  await action();
  passed++;
  console.log(`PASS ${name}`);
}

for (const c of fixture.cases) {
  await test(`parity with the app: ${c.name}`, () => {
    const a = analyze(ledger, c.filter);
    for (const key of ['income', 'expense', 'refunds', 'pendingExpense', 'extraordinary', 'recurring', 'transfers', 'result']) {
      assert.equal(a[key], c.expected[key], key);
    }
    assert.deepEqual(a.categories, c.expected.categories);
  });
}

await test('month helpers reproduce the app periods', () => {
  const month = monthFilter('2026-10', today);
  assert.deepEqual(month, fixture.cases.find(c => c.name === 'month').filter);
  assert.deepEqual(previousMonth(month, true), fixture.cases.find(c => c.name === 'previous_partial').filter);
  assert.deepEqual(monthFilter('2026-02', today), { from: '2026-02-01', to: '2026-02-28' });
  assert.deepEqual(previousMonth({ from: '2026-03-01', to: '2026-03-31' }, true), { from: '2026-02-01', to: '2026-02-28' });
  assert.deepEqual(previousMonth({ from: '2026-01-01', to: '2026-01-15' }, true), { from: '2025-12-01', to: '2025-12-15' });
});

await test('other currencies are reported apart, never converted', () => {
  const a = analyze(ledger, monthFilter('2026-10', today));
  assert.deepEqual(a.unconverted, { USD: 1500 });
});

await test('summary: balances, spending, comparison and exclusions', () => {
  const s = callTool('get_financial_summary', { month: '2026-10' }, ledger, today);
  assert.equal(s.accounts_balance, 3300);
  assert.equal(s.cards_balance, -100);
  assert.equal(s.spending, 1573.25);
  assert.equal(s.income, 5000);
  assert.equal(s.refunds, 20);
  assert.equal(s.result, 3446.75);
  assert.equal(s.transfers_and_reserves_excluded, 300);
  assert.equal(s.previous_spending, 50);
  assert.equal(s.spending_change_percent, 3046.5);
  assert.deepEqual(s.not_converted_other_currencies, { USD: 15 });
  assert.equal(s.top_categories[0].category, 'Categoria health');
});

await test('transactions: filters, search, limit and spending flag', () => {
  const r = callTool('list_transactions', { from: '2026-10-01', to: '2026-10-31', search: 'fatura' }, ledger, today);
  assert.equal(r.total_found, 1);
  assert.equal(r.transactions[0].counts_as_spending, false, 'invoice payment is not spending');
  const pending = callTool('get_transaction', { id: 't-pending' }, ledger, today).transaction;
  assert.equal(pending.status, 'pendente');
  assert.equal(pending.counts_as_spending, false);
  const card = callTool('list_transactions', { account_id: 'card', from: '2026-10-01', to: '2026-10-31' }, ledger, today);
  assert.equal(card.transactions[0].installment, '1/3');
  const limited = callTool('list_transactions', { from: '2026-09-01', to: '2026-10-31', limit: 2 }, ledger, today);
  assert.equal(limited.transactions.length, 2);
  assert.equal(limited.truncated, true);
  assert(limited.transactions[0].date >= limited.transactions[1].date, 'newest first');
});

await test('arguments are validated, never trusted', () => {
  const bad = [
    ['list_transactions', { from: '20/10/2026' }],
    ['list_transactions', { limit: 1000 }],
    ['list_transactions', { from: '2026-10-10', to: '2026-10-01' }],
    ['list_transactions', { sql: 'drop table' }],
    ['get_spending_by_category', { from: '2026-10-01' }],
    ['get_financial_summary', { month: '2026-13' }],
    ['get_upcoming_bills', { days: 365 }],
    ['get_transaction', { id: 'missing' }],
    ['get_accounts', { extra: 1 }],
    ['get_accounts', []],
  ];
  for (const [name, args] of bad) {
    assert.throws(() => callTool(name, args, ledger, today), ToolInputError, `${name} ${JSON.stringify(args)}`);
  }
});

await test('category comparison uses an equal previous period', () => {
  const r = callTool('get_spending_by_category', { from: '2026-10-01', to: '2026-10-20', compare_previous: true }, ledger, today);
  assert.equal(r.total, 1573.25);
  assert.deepEqual([r.previous.from, r.previous.to], ['2026-09-11', '2026-09-30']);
  assert.equal(r.previous.total, 70);
});

await test('upcoming bills: pending due soon and expected recurring', () => {
  const r = callTool('get_upcoming_bills', { days: 30 }, ledger, today);
  assert.equal(r.pending_expenses.length, 1);
  assert.equal(r.pending_expenses[0].due, '2026-10-25');
  assert.equal(r.pending_expenses[0].overdue, false);
  assert.equal(r.recurring_expected[0].next_date, '2026-11-15');
  assert.equal(r.recurring_expected[0].kind, 'previsto');
});

// ── Protocol ─────────────────────────────────────────────────────────────
const token = 'nexo_mcp_' + 'a'.repeat(64);
const audit = [];
let loadFails = false;
const handler = createHandler({
  authenticate: async t => (t === token ? { id: 'c1', ownerId: 'u1', datasetId: 'd1' } : null),
  load: async () => { if (loadFails) throw new Error('db down: secret detail'); return ledger; },
  audit: async (_c, tool, ok) => { audit.push([tool, ok]); },
  today: () => today,
});
const post = (body, auth = token, extra = {}) => handler(new Request('https://x.supabase.co/functions/v1/nexo-mcp', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', ...(auth ? { Authorization: `Bearer ${auth}` } : {}), ...extra },
  body: typeof body === 'string' ? body : JSON.stringify(body),
}));
const rpcCall = (method, params, id = 1) => ({ jsonrpc: '2.0', id, method, params });

await test('requests without a valid connector token are refused', async () => {
  for (const auth of [null, 'nexo_mcp_short', 'nexo_mcp_' + 'b'.repeat(64)]) {
    const response = await post(rpcCall('tools/list', {}), auth);
    assert.equal(response.status, 401);
    assert(response.headers.get('WWW-Authenticate'));
  }
});

await test('initialize negotiates a supported protocol version', async () => {
  const known = await (await post(rpcCall('initialize', { protocolVersion: '2025-06-18', capabilities: {}, clientInfo: { name: 'test', version: '1' } }))).json();
  assert.equal(known.result.protocolVersion, '2025-06-18');
  assert.equal(known.result.serverInfo.name, 'nexo');
  assert(known.result.capabilities.tools);
  const unknown = await (await post(rpcCall('initialize', { protocolVersion: '1999-01-01' }))).json();
  assert.equal(unknown.result.protocolVersion, '2025-06-18');
});

await test('notifications get 202 without body; GET is not offered', async () => {
  const note = await post({ jsonrpc: '2.0', method: 'notifications/initialized' });
  assert.equal(note.status, 202);
  const get = await handler(new Request('https://x.supabase.co/functions/v1/nexo-mcp', { headers: { Authorization: `Bearer ${token}` } }));
  assert.equal(get.status, 405);
});

await test('tools are listed as read-only with schemas', async () => {
  const list = (await (await post(rpcCall('tools/list', {}))).json()).result.tools;
  assert.equal(list.length, tools.length);
  assert(list.every(t => t.annotations.readOnlyHint === true && t.inputSchema.type === 'object'));
  assert(!list.some(t => /create|update|delete/.test(t.name)), 'no write tools yet');
});

await test('tool call returns text and structured content, audited', async () => {
  audit.length = 0;
  const r = (await (await post(rpcCall('tools/call', { name: 'get_financial_summary', arguments: { month: '2026-10' } }))).json()).result;
  assert.equal(r.isError, false);
  assert.equal(r.structuredContent.spending, 1573.25);
  assert.equal(JSON.parse(r.content[0].text).spending, 1573.25);
  assert.deepEqual(audit, [['get_financial_summary', true]]);
});

await test('tool failures are explicit and leak nothing internal', async () => {
  const bad = (await (await post(rpcCall('tools/call', { name: 'list_transactions', arguments: { limit: 0 } }))).json()).result;
  assert.equal(bad.isError, true);
  loadFails = true;
  const down = (await (await post(rpcCall('tools/call', { name: 'get_accounts', arguments: {} }))).json()).result;
  loadFails = false;
  assert.equal(down.isError, true);
  assert(!down.content[0].text.includes('secret'));
  const unknownTool = await (await post(rpcCall('tools/call', { name: 'delete_everything' }))).json();
  assert.equal(unknownTool.error.code, -32602);
  const unknownMethod = await (await post(rpcCall('resources/list', {}))).json();
  assert.equal(unknownMethod.error.code, -32601);
});

await test('malformed, oversized and batched requests are handled', async () => {
  assert.equal((await post('{nope')).status, 400);
  assert.equal((await post('x'.repeat(70000))).status, 413);
  assert.equal((await post([])).status, 400);
  const batch = await (await post([rpcCall('ping', {}, 1), { jsonrpc: '2.0', method: 'notifications/initialized' }, rpcCall('ping', {}, 2)])).json();
  assert.deepEqual(batch.map(r => r.id), [1, 2]);
});

console.log(`NEXO MCP: ${passed} tests passed; synthetic fixture only.`);
