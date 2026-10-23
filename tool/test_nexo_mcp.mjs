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

await test('Claude.ai URL form: token as the last path segment', async () => {
  const at = (path) => handler(new Request(`https://x.supabase.co/functions/v1/nexo-mcp/${path}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(rpcCall('tools/list', {})),
  }));
  assert.equal((await at(token)).status, 200);
  assert.equal((await at('nexo_mcp_' + 'b'.repeat(64))).status, 401);
  assert.equal((await at('')).status, 401, 'the bare function URL needs a token');
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

// ── Change tools: requests only ────────────────────────────────────────
const { callAction } = await import('../supabase/functions/nexo-mcp/actions.ts');
function queue() {
  const q = { items: [], ignored: [], deps: null };
  q.deps = {
    enqueue: async (kind, args) => { const id = `00000000-0000-4000-8000-${String(q.items.length).padStart(12, '0')}`; q.items.push({ id, kind, args, status: 'pending' }); return { id, status: 'pending' }; },
    request: async (id) => q.items.find(r => r.id === id) ?? null,
    suggestions: async (limit) => [{ id: 'pluggy:a', bank: 'Banco', amount_cents: 3290, kind: 'expense', medium: 'credit', description: 'Mercado', occurred_at: Date.parse('2026-10-19T12:00:00Z'), settled: true, installment: null }].slice(0, limit),
    ignoreSuggestions: async (ids, before) => { q.ignored.push([ids, before]); return ids ? ids.length : 7; },
  };
  return q;
}
const withIncome = { ...ledger, categories: [...ledger.categories, { id: 'pay', name: 'Salário', type: 'income' }] };
const act = (q, name, args, l = withIncome) => callAction(name, args, l, today, q.deps);

await test('lançar queues a request with validated ids and exact cents', async () => {
  const q = queue();
  const r = await act(q, 'add_transaction', { type: 'expense', amount: 32.9, description: 'iFood', account_id: 'card', category_id: 'food_exp' });
  assert.equal(r.status, 'pendente');
  assert.deepEqual(q.items[0].args, { type: 'expense', amount_cents: 3290, description: 'iFood', account_id: 'card', category_id: 'food_exp', date: today, note: '' });
  await act(q, 'add_transaction', { type: 'income', amount: 5000, description: 'Salário', account_id: 'bank', category_id: 'pay', date: '2026-10-05' });
  assert.equal(q.items[1].args.date, '2026-10-05');
});

await test('lançar refuses what the app would refuse, before queueing', async () => {
  const q = queue();
  const bad = [
    { type: 'expense', amount: 0, description: 'x', account_id: 'bank', category_id: 'food_exp' },
    { type: 'expense', amount: 1.234, description: 'x', account_id: 'bank', category_id: 'food_exp' },
    { type: 'expense', amount: 10, description: 'x', account_id: 'nope', category_id: 'food_exp' },
    { type: 'expense', amount: 10, description: 'x', account_id: 'bank', category_id: 'pay' },
    { type: 'pix', amount: 10, description: 'x', account_id: 'bank', category_id: 'food_exp' },
    { type: 'expense', amount: 10, description: 'x', account_id: 'bank', category_id: 'food_exp', date: '20/10/2026' },
    { type: 'expense', amount: 10, description: 'x', account_id: 'bank', category_id: 'food_exp', sneaky: 1 },
  ];
  for (const args of bad) await assert.rejects(act(q, 'add_transaction', args), ToolInputError);
  await assert.rejects(act(q, 'add_transfer', { from_account_id: 'bank', to_account_id: 'bank', amount: 10 }), ToolInputError);
  assert.equal(q.items.length, 0, 'nothing reached the queue');
});

await test('transfer, correction and deletion become requests', async () => {
  const q = queue();
  await act(q, 'add_transfer', { from_account_id: 'bank', to_account_id: 'card', amount: 500, note: 'fatura' });
  assert.equal(q.items[0].kind, 'transfer.add');
  assert.equal(q.items[0].args.amount_cents, 50000);
  await act(q, 'update_transaction', { id: 't-food', amount: 40, category_id: 'shopping' });
  assert.deepEqual(q.items[1].args, { id: 't-food', amount_cents: 4000, category_id: 'shopping' });
  await assert.rejects(act(q, 'update_transaction', { id: 't-food' }), ToolInputError, 'nothing to change');
  await assert.rejects(act(q, 'update_transaction', { id: 't-salary', category_id: 'food_exp' }, withIncome), ToolInputError);
  await act(q, 'delete_transaction', { id: 't-market' });
  assert.equal(q.items[2].kind, 'transaction.delete');
  await assert.rejects(act(q, 'delete_transaction', { id: 'missing' }), ToolInputError);
  const invest = { ...ledger, transactions: [...ledger.transactions, { id: 'investment:op1', type: 'expense', amount: 10, account_id: 'bank' }] };
  await assert.rejects(act(q, 'delete_transaction', { id: 'investment:op1' }, invest), ToolInputError);
});

await test('suggestions: listed in reais, confirmed as request, ignored directly', async () => {
  const q = queue();
  const list = await act(q, 'list_suggestions', { limit: 5 });
  assert.equal(list.suggestions[0].amount, 32.9);
  assert.equal(list.suggestions[0].medium, 'cartão');
  await act(q, 'confirm_suggestion', { id: 'pluggy:a', account_id: 'card', category_id: 'food_exp' });
  assert.deepEqual(q.items[0], { id: q.items[0].id, kind: 'suggestion.confirm', status: 'pending',
    args: { id: 'pluggy:a', account_id: 'card', category_id: 'food_exp', type: 'expense', description: undefined } });
  await assert.rejects(act(q, 'confirm_suggestion', { id: 'notification:x', account_id: 'card', category_id: 'food_exp' }), ToolInputError);
  assert.equal((await act(q, 'ignore_suggestions', { before: '2026-10-01' })).ignored, 7);
  assert.equal(q.ignored[0][1], Date.parse('2026-10-01T00:00:00-03:00'));
  await assert.rejects(act(q, 'ignore_suggestions', {}), ToolInputError);
});

await test('request status reads back the outcome', async () => {
  const q = queue();
  const { request_id } = await act(q, 'delete_transaction', { id: 't-market' });
  assert.match((await act(q, 'get_request_status', { id: request_id })).status, /pendente/);
  q.items[0].status = 'rejected';
  q.items[0].result = { reason: 'não encontrado' };
  const r = await act(q, 'get_request_status', { id: request_id });
  assert.equal(r.status, 'recusado pelo Nexo');
  assert.equal(r.result.reason, 'não encontrado');
});

await test('change tools are listed with honest hints only when the queue exists', async () => {
  const withActions = createHandler({
    authenticate: async t => (t === token ? { id: 'c1', ownerId: 'u1', datasetId: 'd1' } : null),
    load: async () => ledger, audit: async () => {}, today: () => today, actions: () => queue().deps,
  });
  const list = async (h) => (await (await h(new Request('https://x.supabase.co/functions/v1/nexo-mcp', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(rpcCall('tools/list', {})),
  }))).json()).result.tools;
  const all = await list(withActions);
  const hint = (n) => all.find(t => t.name === n).annotations;
  assert.equal(hint('add_transaction').readOnlyHint, false);
  assert.equal(hint('delete_transaction').destructiveHint, true);
  assert.equal(hint('list_suggestions').readOnlyHint, true);
  assert(all.some(t => t.name === 'get_categories'));
  assert(!(await list(handler)).some(t => t.name === 'add_transaction'), 'read-only deployment has no change tools');
});

// ── Recurring, budgets, categories, goals, invoices ────────────────────
const richer = {
  ...withIncome,
  recurring: [...ledger.recurring,
    { id: 'parc', name: 'Notebook 10x', payment_type: 'expense', recurring_type: 'installment', amount: 300,
      next_date: '2026-10-25T00:00:00.000', end_date: '2027-05-25T00:00:00.000', account_id: 'card', category_id: 'shopping', freq_val: 1, freq_unit: 'months' }],
  budgets: [{ id: 'b1', category_id: 'food_exp', amount: 500, period: 'monthly' }],
  goals: [{ id: 'g1', name: 'Reserva', target_amount: 10000, current_amount: 2500 }],
};
await test('recurring: listed with next date; pay keeps the expected occurrence and real amount', async () => {
  const q = queue();
  const list = await act(q, 'get_recurring', {}, richer);
  assert.deepEqual(list.recurring.map(r => [r.id, r.next_date]), [['parc', '2026-10-25'], ['stream', '2026-11-15']]);
  await act(q, 'pay_recurring', { id: 'stream', amount: 198.15 }, richer);
  assert.deepEqual(q.items[0].args, { id: 'stream', expected_date: '2026-11-15', amount_cents: 19815 });
  await assert.rejects(act(q, 'pay_recurring', { id: 'stream', date: '2026-10-15' }, richer), ToolInputError,
    'a different occurrence than the next one is refused');
  await assert.rejects(act(q, 'skip_recurring', { id: 'parc' }, richer), ToolInputError, 'installments cannot be skipped');
  await act(q, 'skip_recurring', { id: 'stream' }, richer);
  assert.equal(q.items[1].kind, 'recurring.skip');
});
await test('recurring: create, update and delete validate before queueing', async () => {
  const q = queue();
  await act(q, 'add_recurring', { name: 'Academia', type: 'expense', amount: 99.9, account_id: 'bank', category_id: 'health', first_date: '2026-11-05' }, richer);
  assert.equal(q.items[0].args.freq_unit, 'months');
  assert.equal(q.items[0].args.amount_cents, 9990);
  await assert.rejects(act(q, 'add_recurring', { name: 'X', type: 'expense', amount: 10, account_id: 'bank', category_id: 'health', first_date: '2026-11-05', kind: 'installment' }, richer), ToolInputError);
  await assert.rejects(act(q, 'add_recurring', { name: 'X', type: 'income', amount: 10, account_id: 'bank', category_id: 'health', first_date: '2026-11-05' }, richer), ToolInputError);
  await act(q, 'update_recurring', { id: 'stream', amount: 44.9 }, richer);
  assert.deepEqual(q.items[1].args, { id: 'stream', amount_cents: 4490 });
  await assert.rejects(act(q, 'update_recurring', { id: 'stream' }, richer), ToolInputError);
  await act(q, 'delete_recurring', { id: 'parc' }, richer);
  assert.equal(q.items.length, 3);
});
await test('budgets, categories, goals and invoices', async () => {
  const q = queue();
  const budgets = await act(q, 'get_budgets', {}, richer);
  assert.equal(budgets.budgets[0].limit, 500);
  assert.equal(typeof budgets.budgets[0].spent, 'number');
  await act(q, 'set_budget', { category_id: 'food_exp', amount: 600 }, richer);
  assert.deepEqual(q.items[0].args, { category_id: 'food_exp', amount_cents: 60000, period: 'monthly' });
  await assert.rejects(act(q, 'set_budget', { category_id: 'pay', amount: 1 }, richer), ToolInputError, 'income category');
  await act(q, 'add_category', { name: 'Pets', type: 'expense' }, richer);
  await assert.rejects(act(q, 'add_category', { name: 'pets', type: 'expense' }, { ...richer, categories: [...richer.categories, { id: 'p', name: 'Pets', type: 'expense' }] }), ToolInputError);
  const goals = await act(q, 'get_goals', {}, richer);
  assert.equal(goals.goals[0].missing, 7500);
  await act(q, 'move_goal', { goal_id: 'g1', account_id: 'bank', amount: 100, direction: 'deposit' }, richer);
  await assert.rejects(act(q, 'move_goal', { goal_id: 'g1', account_id: 'card', amount: 100, direction: 'deposit' }, richer), ToolInputError);
  await act(q, 'pay_card_invoice', { card_id: 'card', from_account_id: 'bank' }, richer);
  assert.deepEqual(q.items.at(-1).args, { card_id: 'card', from_account_id: 'bank', invoice: 'closed' });
  await assert.rejects(act(q, 'pay_card_invoice', { card_id: 'bank', from_account_id: 'bank' }, richer), ToolInputError);
  await assert.rejects(act(q, 'settle_transaction', { id: 't-food' }, richer), ToolInputError, 'already paid');
  await act(q, 'settle_transaction', { id: 't-pending' }, richer);
  assert.equal(q.items.at(-1).kind, 'transaction.settle');
});

const everything = {
  ...richer,
  investments: [{ id: 'inv1', name: 'CDB fictício', asset_class: 'Renda fixa', ticker: '', price_micros: 1000000, price_at: '2026-10-01T00:00:00.000Z', archived: 0 }],
  investmentOperations: [{ id: 'op1', investment_id: 'inv1', kind: 'buy', quantity: 2000000, cents: 200 }],
  loans: [{ id: 'loan1', name: 'Financiamento fictício', principal: 1200, start_date: '2026-01-01', end_date: '2027-01-01', is_settled: 0, account_id: 'bank' }],
  loanPayments: [{ id: 'lp1', loan_id: 'loan1', amount: 100 }, { id: 'lp2', loan_id: 'loan1', amount: 0 }],
  lended: [{ id: 'len1', person_id: 'per1', type: 'lent', amount: 50, date: '2026-10-01', is_settled: 0 }],
  lendedPeople: [{ id: 'per1', name: 'Pessoa fictícia' }],
  assets: [{ id: 'as1', name: 'Carro', value: 40000, currency: 'BRL' }],
  wishlist: [{ id: 'w1', name: 'Fone', target_price: 599.9, priority: 'high', is_purchased: 0 }],
};
await test('balance adjustment is its own request, from the synced balance', async () => {
  const q = queue();
  const accounts = callTool('get_accounts', {}, everything, today).accounts;
  const bank = accounts.find((a) => a.id === 'bank');
  const r = await act(q, 'adjust_account_balance', { account_id: 'bank', balance: bank.balance + 67.26 }, everything);
  assert.equal(q.items[0].kind, 'account.adjust');
  assert.deepEqual(q.items[0].args, {
    id: 'bank', expected_cents: Math.round(bank.balance * 100), balance_cents: Math.round(bank.balance * 100) + 6726,
  });
  assert.equal(r.to, Math.round(bank.balance * 100 + 6726) / 100);
  await assert.rejects(act(q, 'adjust_account_balance', { account_id: 'bank', balance: bank.balance }, everything), ToolInputError,
    'same balance is refused');
  await assert.rejects(act(q, 'adjust_account_balance', { account_id: 'bank', balance: 1.234 }, everything), ToolInputError);
});
await test('accounts, categories and goals: create, change, delete', async () => {
  const q = queue();
  await act(q, 'add_account', { name: 'Cartão novo', type: 'credit', balance: -10.5, due_day: 10, credit_limit: 3000 }, everything);
  assert.deepEqual(q.items[0].args, { name: 'Cartão novo', type: 'credit', balance_cents: -1050, statement_day: undefined, due_day: 10, credit_limit_cents: 300000 });
  await act(q, 'add_account', { name: 'Carteira', type: 'cash' }, everything);
  assert.deepEqual(q.items[1].args, { name: 'Carteira', type: 'cash', balance_cents: 0 });
  await assert.rejects(act(q, 'update_account', { id: 'bank' }, everything), ToolInputError, 'nothing to change');
  await act(q, 'update_account', { id: 'bank', name: 'Banco renomeado' }, everything);
  assert.deepEqual(q.items[2].args, { id: 'bank', name: 'Banco renomeado' });
  await assert.rejects(act(q, 'delete_category', { id: 'food_exp' }, everything), ToolInputError, 'category in use');
  await act(q, 'add_goal', { name: 'Viagem', target: 3000, target_date: '2027-06-01' }, everything);
  assert.deepEqual(q.items.at(-1).args, { name: 'Viagem', target_cents: 300000, target_date: '2027-06-01' });
  await assert.rejects(act(q, 'delete_goal', { id: 'g1' }, everything), ToolInputError, 'goal with money');
  await act(q, 'update_goal', { id: 'g1', target: 12000 }, everything);
  assert.equal(q.items.at(-1).args.target_cents, 1200000);
});
await test('investments, loans, money lent, assets and wishlist', async () => {
  const q = queue();
  const inv = await act(q, 'get_investments', {}, everything);
  assert.deepEqual(inv.investments.map((i) => [i.id, i.quantity]), [['inv1', 2]]);
  await act(q, 'record_investment_operation', { investment_id: 'inv1', kind: 'sell', quantity: 0.5, total: 60, date: '2026-10-10', cash_account_id: 'bank' }, everything);
  assert.equal(q.items[0].args.quantity_micros, 500000);
  assert.equal(q.items[0].args.cents, 6000);
  assert.equal(typeof q.items[0].args.created_at, 'string');
  await assert.rejects(act(q, 'record_investment_operation', { investment_id: 'inv1', kind: 'income', quantity: 1, total: 5, date: '2026-10-10' }, everything), ToolInputError);
  await assert.rejects(act(q, 'record_investment_operation', { investment_id: 'inv1', kind: 'buy', quantity: 1, total: 5, date: '2026-10-10', cash_account_id: 'card' }, everything), ToolInputError, 'card is not cash');
  await act(q, 'add_investment', { name: 'Tesouro fictício', asset_class: 'Renda fixa', quantity: 1, total: 100, date: '2026-10-01' }, everything);
  assert.equal(q.items.at(-1).kind, 'investment.add');
  await act(q, 'update_investment_price', { investment_id: 'inv1', price: 1.2 }, everything);
  assert.deepEqual(q.items.at(-1).args, { investment_id: 'inv1', price_cents: 120, date: null });

  const loans = await act(q, 'get_loans', {}, everything);
  assert.deepEqual([loans.loans[0].paid, loans.loans[0].payments, loans.loans[0].skipped], [100, 1, 1]);
  await act(q, 'pay_loan_installment', { id: 'loan1', amount: 110 }, everything);
  assert.deepEqual(q.items.at(-1).args, { id: 'loan1', amount_cents: 11000 });
  await act(q, 'skip_loan_installment', { id: 'loan1' }, everything);
  assert.equal(q.items.at(-1).kind, 'loan.skip');

  const lended = await act(q, 'get_lended', {}, everything);
  assert.equal(lended.lended[0].person, 'Pessoa fictícia');
  await act(q, 'add_lended', { person: 'Outra pessoa', type: 'borrowed', amount: 20, date: '2026-10-20' }, everything);
  assert.equal(q.items.at(-1).args.amount_cents, 2000);
  await act(q, 'settle_lended', { id: 'len1' }, everything);
  assert.equal(q.items.at(-1).kind, 'lended.settle');

  assert.equal((await act(q, 'get_assets', {}, everything)).assets[0].value, 40000);
  await act(q, 'update_asset', { id: 'as1', value: 38000 }, everything);
  assert.deepEqual(q.items.at(-1).args, { id: 'as1', value_cents: 3800000 });
  await act(q, 'delete_asset', { id: 'as1' }, everything);
  assert.equal((await act(q, 'get_wishlist', {}, everything)).wishlist[0].price, 599.9);
  await act(q, 'update_wishlist_item', { id: 'w1', purchased: true }, everything);
  assert.deepEqual(q.items.at(-1).args, { id: 'w1', purchased: true });
  await act(q, 'add_wishlist_item', { name: 'Cadeira', price: 900 }, everything);
  assert.equal(q.items.at(-1).args.priority, 'medium');
});
await test('every new change tool is listed and annotated', async () => {
  const withActions = createHandler({
    authenticate: async t => (t === token ? { id: 'c1', ownerId: 'u1', datasetId: 'd1' } : null),
    load: async () => ledger, audit: async () => {}, today: () => today, actions: () => queue().deps,
  });
  const listed = (await (await withActions(new Request('https://x.supabase.co/functions/v1/nexo-mcp', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(rpcCall('tools/list', {})),
  }))).json()).result.tools;
  const byName = Object.fromEntries(listed.map((t) => [t.name, t]));
  for (const name of ['adjust_account_balance', 'add_account', 'delete_category', 'add_goal', 'record_investment_operation',
    'pay_loan_installment', 'add_lended', 'add_asset', 'add_wishlist_item']) {
    assert.ok(byName[name], name);
    assert.equal(byName[name].annotations.readOnlyHint, false, name);
  }
  assert.equal(byName.get_loans.annotations.readOnlyHint, true);
  assert.equal(byName.delete_account.annotations.destructiveHint, true);
});

await test('card invoices: the bank split, payment after closing, limit used', async () => {
  const q = queue();
  const buy = (id, amount, date) => ({ id, type: 'expense', amount, description: id, account_id: 'nu',
    category_id: 'food_exp', date: `${date}T12:00:00.000` });
  const card = { ...withIncome,
    accounts: [...withIncome.accounts, { id: 'nu', name: 'Cartão roxo', type: 'credit', currency: 'BRL',
      statement_day: 19, due_day: 26, credit_limit: 650 }],
    transactions: [...withIncome.transactions,
      buy('a', 300, '2026-09-19'), buy('b', 150.92, '2026-10-18'),
      buy('c', 29.24, '2026-10-19'), buy('d', 39.90, '2026-10-19'), buy('e', 26.49, '2026-10-19'),
      buy('f', 17.99, '2026-10-19'), buy('g', 26.42, '2026-10-21'), buy('h', 30.85, '2026-10-21'),
      buy('i', 26.42, '2026-10-21'), buy('j', 16.28, '2026-10-26')],
    invoicePayments: [{ id: 'p', card_id: 'nu', cycle_end: '2026-10-19', amount: 30 }],
  };
  const r = await act(q, 'get_card_invoices', { card_id: 'nu' }, card);
  const [nov, oct] = r.cards[0].invoices;
  assert.deepEqual([oct.closing_date, oct.total, oct.paid, oct.remaining, oct.due_date],
    ['2026-10-19', 450.92, 30, 420.92, '2026-10-26']);
  assert.deepEqual([nov.closing_date, nov.purchases_from, nov.total, nov.status],
    ['2026-11-19', '2026-10-19', 213.59, 'aberta']);
  assert.equal(r.cards[0].limit_used_percent, Math.round(634.51 / 650 * 100));
  assert.equal(q.items.length, 0, 'reading never queues');
});
await test('refusals the assistant can act on; status says how long it waits', async () => {
  const failing = (message) => ({ ...queue().deps, enqueue: async () => { throw new Error(`rpc_400:${message}`); } });
  await assert.rejects(callAction('add_asset', { name: 'Carro', value: 10 }, withIncome, today, failing('kind_unsupported')),
    (e) => e instanceof ToolInputError && /Atualize o app/.test(e.message));
  await assert.rejects(callAction('add_asset', { name: 'Carro', value: 10 }, withIncome, today, failing('too_many_pending')),
    (e) => e instanceof ToolInputError && /100 pedidos/.test(e.message));
  const q = queue();
  const { request_id } = await act(q, 'add_asset', { name: 'Carro', value: 10 });
  q.items[0].created_at = new Date(Date.now() - 7 * 60000).toISOString();
  const s = await act(q, 'get_request_status', { id: request_id });
  assert.equal(s.waiting_minutes, 7);
  assert.match(s.next_step, /Nexo estiver aberto/);
});
await test('ignoring in batch can be previewed first', async () => {
  const q = queue();
  const preview = await act(q, 'ignore_suggestions', { before: '2026-10-01', preview: true });
  assert.equal(typeof preview.would_ignore, 'number');
  assert.match(preview.note, /nada foi alterado/);
  assert.equal(q.ignored.length, 0);
});

await test('bank data until: an empty day is not "no spending" when today did not arrive', async () => {
  const q = queue();
  q.deps.bankStatus = async () => [
    { bank: 'Nubank', state: 'ok', bank_updated_at: '2026-10-19T09:00:00.000Z' },
    { bank: 'Inter', state: 'ok', bank_updated_at: '2026-10-20T09:30:00.000Z' },
  ];
  const r = await act(q, 'get_bank_sync_status', {});
  assert.deepEqual(r.banks.map((b) => [b.bank, b.data_until, b.today_arrived]),
    [['Nubank', '2026-10-19 06:00', false], ['Inter', '2026-10-20 06:30', true]]);
  assert.match(r.note, /Não conclua que não houve gasto/);
  const list = await act(q, 'list_suggestions', {});
  assert.equal(list.bank_data.banks.length, 2);
  const old = queue();
  const none = await act(old, 'get_bank_sync_status', {});
  assert.deepEqual(none.banks, []);
});

console.log(`NEXO MCP: ${passed} tests passed; synthetic fixture only.`);
