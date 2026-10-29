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

await test('daily digest: what came in and out, card purchases, alerts and data freshness', async () => {
  const q = queue();
  q.deps.bankStatus = async () => [{ bank: 'Nubank', state: 'ok', bank_updated_at: '2026-10-19T09:00:00.000Z' }];
  const t = (id, type, amount, account, category, date = '2026-10-20T12:00:00.000') =>
    ({ id, type, amount, description: id, account_id: account, category_id: category, date });
  const dayLedger = { ...withIncome,
    accounts: [...withIncome.accounts, { id: 'nu', name: 'Cartão roxo', type: 'credit', currency: 'BRL' }],
    transactions: [...withIncome.transactions,
      t('Trabalho Ifood', 'income', 100, 'bank', 'pay'),
      t('Batata frita', 'expense', 13.99, 'nu', 'food_exp'),
      t('Padaria', 'expense', 8, 'bank', 'food_exp'),
      t('Para a reserva', 'expense', 50, 'bank', 'food_exp'),
      t('Ontem', 'expense', 99, 'bank', 'food_exp', '2026-10-19T12:00:00.000')],
    metadata: [...(withIncome.metadata ?? []),
      { transaction_id: 'Para a reserva', exclude_from_spending: 1, source: 'transfer:x' }],
  };
  const r = await act(q, 'get_daily_digest', {}, dayLedger);
  assert.equal(r.date, '2026-10-20');
  assert.deepEqual(r.incomes.map((x) => x.description), ['Trabalho Ifood']);
  assert.deepEqual(r.card_purchases.map((x) => [x.description, x.amount]), [['Batata frita', 13.99]]);
  assert.equal(r.expenses.some((x) => x.description === 'Para a reserva'), false, 'transfers are not spending');
  assert.equal(r.expenses.some((x) => x.description === 'Ontem'), false);
  assert.equal(r.bank_data.banks[0].today_arrived, false);
  await assert.rejects(act(q, 'get_daily_digest', { date: '2026-10-21' }, dayLedger), ToolInputError);
});

// ── Parity with the app (29/10/2026) ───────────────────────────────────
// Synthetic scenario with the rules of the reported case (card closing on the
// 19th, due on the 26th, R$ 650 limit, a reference income); no real data.
const { createdIdPrefix, actions } = await import('../supabase/functions/nexo-mcp/actions.ts');
const { parityActions, categoryIcons } = await import('../supabase/functions/nexo-mcp/parity_actions.ts');
const { settingDefs } = await import('../supabase/functions/nexo-mcp/settings.ts');
const { envelopes } = await import('../supabase/functions/nexo-mcp/envelopes.ts');
const { readOnlyActions, instructions } = await import('../supabase/functions/nexo-mcp/mcp.ts');

function smartQueue() {
  const q = queue();
  q.keys = [];
  q.deps.enqueue = async (kind, args, key) => {
    q.keys.push(key);
    const same = q.items.find(r => (key ? r.key === key : r.kind === kind && JSON.stringify(r.args) === JSON.stringify(args)));
    if (same) return { id: same.id, status: same.status, deduplicated: true };
    const id = `00000000-0000-4000-8000-${String(q.items.length).padStart(12, '0')}`;
    q.items.push({ id, kind, args, key, status: 'pending' });
    return { id, status: 'pending', deduplicated: false };
  };
  q.deps.recent = async (limit) => q.items.slice(-limit).reverse().map(r => ({
    id: r.id, kind: r.kind, status: r.status, created_at: '2026-10-29T12:00:00Z', message: r.result?.message ?? null,
    reason: r.result?.reason ?? null, undoable: r.status === 'done' && !!r.result?.undo && !r.result?.undone_at,
    undone_at: r.result?.undone_at ?? null,
  }));
  return q;
}
const tday = '2026-10-29';
const tx = (id, amount, date, account, category, extra = {}) =>
  ({ id, type: 'expense', amount, description: id, account_id: account, category_id: category, date: `${date}T12:00:00.000`, note: '', ...extra });
const scenario = {
  mainCurrency: 'BRL',
  accounts: [
    { id: 'main', name: 'Conta principal', type: 'bank', currency: 'BRL' },
    { id: 'nu', name: 'Nubank', type: 'credit', currency: 'BRL', statement_day: 19, due_day: 26, credit_limit: 650 },
  ],
  balances: { main: 2000_000000, nu: -300_000000 },
  categories: [
    { id: 'moradia', name: 'Moradia', type: 'expense', envelope: 'fixed', color_value: 0xFF1E88E5, icon_code_point: 18 },
    { id: 'mercado', name: 'Mercado', type: 'expense', envelope: 'fixed' },
    { id: 'delivery', name: 'Delivery', type: 'expense', envelope: 'comfort' },
    { id: 'bar', name: 'Bar', type: 'expense', envelope: 'pleasures' },
    { id: 'livros', name: 'Livros', type: 'expense' },
    { id: 'roupas', name: 'Roupas', type: 'expense' },
    { id: 'salario', name: 'Salário', type: 'income' },
    { id: 'ajuste', name: 'Ajuste de saldo', type: 'income' },
  ],
  transactions: [
    tx('aluguel', 800, '2026-10-05', 'main', 'moradia'),
    tx('feira', 120.5, '2026-10-10', 'nu', 'mercado'),
    tx('ifood', 45.9, '2026-10-19', 'nu', 'delivery'),
    tx('ifood2', 39.9, '2026-10-21', 'nu', 'delivery'),
    tx('chopp', 60, '2026-10-12', 'main', 'bar'),
    tx('livro', 80.28, '2026-10-14', 'main', 'livros'),
    tx('camisa', 1240, '2026-10-15', 'main', 'roupas'),
    tx('luz-pendente', 150, '2026-10-28', 'main', 'moradia'),
    tx('setembro', 999, '2026-09-28', 'main', 'moradia'),
    { id: 'salario-out', type: 'income', amount: 1800, description: 'Salário', account_id: 'main', category_id: 'salario', date: '2026-10-05T12:00:00.000', note: '' },
    { id: 'acerto-antigo', type: 'income', amount: 67.26, description: 'Ajuste', account_id: 'main', category_id: 'ajuste', date: '2026-10-08T12:00:00.000', note: '' },
    { id: 'reserva', type: 'expense', amount: 100, description: 'Transferência enviada', account_id: 'main', category_id: '', date: '2026-10-09T12:00:00.000', note: '' },
    tx('parcela', 50, '2026-10-11', 'nu', 'roupas'),
  ],
  metadata: [
    { transaction_id: 'luz-pendente', status: 'pending', due_date: '2026-11-05T00:00:00.000' },
    { transaction_id: 'reserva', exclude_from_spending: 1, source: 'transfer:reserva' },
    { transaction_id: 'parcela', installment_current: 1, installment_total: 3, source: 'installment' },
  ],
  recurring: [
    { id: 'net', name: 'Internet', payment_type: 'expense', amount: 99.9, next_date: '2026-11-10T00:00:00.000', account_id: 'main', category_id: 'moradia', freq_val: 1, freq_unit: 'months', recurring_type: 'subscription' },
    { id: 'sal', name: 'Salário', payment_type: 'income', amount: 1800, next_date: '2026-11-05T00:00:00.000', account_id: 'main', category_id: 'salario', freq_val: 1, freq_unit: 'months', recurring_type: 'subscription' },
    { id: 'spotify', name: 'Spotify', payment_type: 'expense', amount: 21.9, next_date: '2026-11-02T00:00:00.000', account_id: 'nu', category_id: 'delivery', freq_val: 1, freq_unit: 'months', recurring_type: 'subscription' },
  ],
  investments: [{ id: 'petr', name: 'PETR4', asset_class: 'Ações', ticker: 'PETR4', price_micros: 40_000000, price_at: '2026-10-28T00:00:00Z', archived: 0 }],
  investmentOperations: [
    { id: 'op-buy', investment_id: 'petr', kind: 'buy', quantity: 10_000000, cents: 38000, date: '2026-10-20T12:00:00.000', cash_account_id: 'main' },
    { id: 'op-old', investment_id: 'petr', kind: 'buy', quantity: 5_000000, cents: 15000, date: '2026-01-10T12:00:00.000' },
  ],
  budgets: [
    { id: 'b-mercado', category_id: 'mercado', amount: 400, period: 'monthly', created_at: '2026-10-21T10:00:00.000' },
    { id: 'b-bar', category_id: 'bar', amount: 100, period: 'weekly', created_at: '2026-09-01T10:00:00.000' },
  ],
  goals: [{ id: 'trip', name: 'Viagem', target_amount: 1000, current_amount: 300 }],
  contributions: [
    { id: 'c1', goal_id: 'trip', amount: 200, type: 'contribution', date: '2026-10-07T12:00:00.000', account_id: 'main' },
    { id: 'c2', goal_id: 'trip', amount: 100, type: 'withdrawal', date: '2026-10-08T12:00:00.000', account_id: 'main' },
  ],
  loans: [{ id: 'carro', name: 'Carro', principal: 10000, start_date: '2026-01-01', end_date: '2027-01-01', is_settled: 0, account_id: 'main' }],
  loanPayments: [{ id: 'lp1', loan_id: 'carro', amount: 900, date: '2026-09-10T12:00:00.000' }],
  lended: [{ id: 'len', person_id: 'ana', type: 'lent', amount: 50, date: '2026-10-01', is_settled: 0, account_id: 'main' }],
  lendedPeople: [{ id: 'ana', name: 'Pessoa fictícia' }, { id: 'bia', name: 'Outra pessoa' }],
  assets: [{ id: 'moto', name: 'Moto', value: 8000, currency: 'BRL' }],
  wishlist: [],
  invoicePayments: [{ id: 'pay-set', card_id: 'nu', cycle_end: '2026-10-19', amount: 100, paid_at: '2026-10-20T12:00:00.000' }],
  importRules: [{ id: 'r-ifood', pattern: 'IFOOD', type: 'expense', category_id: 'delivery', subcategory: '' }],
  sharedSettings: [
    { key: 'referenceIncome', value: '1800', updated_at: '2026-10-28T00:00:00Z' },
    { key: 'envelopeShares', value: JSON.stringify({ fixed: 50, comfort: 10, goals: 10, pleasures: 10, knowledge: 5, freedom: 15 }), updated_at: '2026-10-28T00:00:00Z' },
  ],
  devices: [{ app_version: '1.13.0+52', kinds: ['category.envelope'], settings: { themeMode: 'dark' }, seen_at: '2026-10-29T10:00:00Z' }],
};
const pact = (q, name, args, l = scenario) => callAction(name, args, l, tday, q.deps);

await test('parity: spending types read like the Orçamento screen', async () => {
  const q = smartQueue();
  const r = await pact(q, 'get_spending_types', { month: '2026-10' });
  assert.equal(r.reference_income, 1800);
  const t = Object.fromEntries(r.types.map((x) => [x.type, x]));
  // Fixed: rent + market + pending light bill (pending counts, as in the app); September stays out.
  assert.deepEqual([t.fixed.share_percent, t.fixed.planned, t.fixed.spent], [50, 900, 1070.5]);
  assert.equal(t.fixed.over, true);
  assert.equal(t.comfort.spent, 85.8, 'both deliveries, the one on the closing day too');
  assert.equal(t.freedom.spent, 380, 'investment purchase of the month');
  assert.equal(t.goals.spent, 200, 'the withdrawal does not count as goal use');
  assert.equal(t.goals.over, false);
  assert.deepEqual(r.without_type.categories_with_spending.map((c) => [c.name, c.spent]), [['Livros', 80.28], ['Roupas', 1290]]);
  assert.equal(r.without_type.spent, 1370.28, 'R$ 1.370,28 em 2 categoria(s) sem tipo');
  assert.equal(r.shares_total, 100);
  assert.equal(q.items.length, 0, 'reading never queues');
  const none = await pact(q, 'get_spending_types', {}, { ...scenario, sharedSettings: [] });
  assert.equal(none.reference_income, null);
  assert.equal(none.types[0].planned, null);
  assert.match(none.note, /set_spending_targets/);
  await assert.rejects(pact(q, 'get_spending_types', { month: '2026-13' }), ToolInputError);
});

await test('parity: Classificar and Ajustar become requests the app validates again', async () => {
  const q = smartQueue();
  const r = await pact(q, 'set_category_type', { assignments: [
    { category_id: 'livros', type: 'knowledge' }, { category_id: 'roupas', type: 'pleasures' }, { category_id: 'bar', type: null }] });
  assert.equal(r.categories, 3);
  assert.deepEqual(q.items[0], { id: q.items[0].id, kind: 'category.envelope', key: undefined, status: 'pending',
    args: { assignments: [{ id: 'livros', envelope: 'knowledge' }, { id: 'roupas', envelope: 'pleasures' }, { id: 'bar', envelope: null }] } });
  await assert.rejects(pact(q, 'set_category_type', { assignments: [{ category_id: 'salario', type: 'fixed' }] }), /receita/);
  await assert.rejects(pact(q, 'set_category_type', { assignments: [{ category_id: 'livros', type: 'luxo' }] }), ToolInputError);
  await assert.rejects(pact(q, 'set_category_type', { assignments: [] }), ToolInputError);
  const shares = { fixed: 30, comfort: 15, goals: 15, pleasures: 10, knowledge: 5, freedom: 25 };
  await pact(q, 'set_spending_targets', { reference_income: 1800, shares });
  assert.deepEqual(q.items.at(-1).args, { values: { referenceIncome: 1800, envelopeShares: shares } });
  await assert.rejects(pact(q, 'set_spending_targets', { shares: { ...shares, fixed: 40 } }), /somam 110%/);
  await assert.rejects(pact(q, 'set_spending_targets', { shares: { fixed: 100 } }), ToolInputError);
  await assert.rejects(pact(q, 'set_spending_targets', {}), ToolInputError);
  await pact(q, 'set_spending_targets', { reference_income: 0 });
  assert.deepEqual(q.items.at(-1).args, { values: { referenceIncome: 0 } });
});

await test('parity: settings are read and changed through one registry', async () => {
  const q = smartQueue();
  const s = await pact(q, 'get_settings', {});
  const shared = Object.fromEntries(s.shared.map((x) => [x.key, x.value]));
  assert.equal(shared.referenceIncome, 1800);
  assert.equal(shared.weekStart, 'monday', 'the app default when nothing is stored');
  assert.deepEqual(s.devices[0].settings, { themeMode: 'dark' });
  await pact(q, 'set_setting', { settings: { weekStart: 'sunday', budgetAlertsEnabled: false, lockedGoalIds: ['trip'] } });
  assert.deepEqual(q.items[0].args, { values: { weekStart: 'sunday', budgetAlertsEnabled: false, lockedGoalIds: ['trip'] } });
  for (const bad of [{ weekStart: 'friday' }, { lockedGoalIds: ['nope'] }, { senha: '1234' }, { dailyReminderTime: '25:00' },
    { currency: 'real' }, { homeCards: [] }]) {
    await assert.rejects(pact(q, 'set_setting', { settings: bad }), ToolInputError, JSON.stringify(bad));
  }
  assert.equal(q.items.length, 1);
});

await test('parity: categories are edited, merged with a preview, and read with their kind', async () => {
  const q = smartQueue();
  const cats = callTool('get_categories', {}, scenario, tday).categories;
  const moradia = cats.find((c) => c.id === 'moradia');
  assert.deepEqual([moradia.spending_type, moradia.spending_type_name, moradia.color, moradia.icon, moradia.transactions, moradia.has_budget],
    ['fixed', 'Custos fixos', '#1E88E5', 18, 3, false]);
  await pact(q, 'update_category', { id: 'livros', spending_type: 'knowledge', color: '#FDD835', icon: 'livro' });
  assert.deepEqual(q.items[0].args, { id: 'livros', envelope: 'knowledge', color: 0xFFFDD835, icon: categoryIcons.indexOf('Livro') + 1 });
  assert.equal(q.items[0].kind, 'category.edit');
  await pact(q, 'update_category', { id: 'bar', spending_type: null });
  assert.deepEqual(q.items[1].args, { id: 'bar', envelope: null });
  await assert.rejects(pact(q, 'update_category', { id: 'livros', name: 'mercado' }), /Já existe/);
  await assert.rejects(pact(q, 'update_category', { id: 'livros', icon: 99 }), ToolInputError);
  await assert.rejects(pact(q, 'update_category', { id: 'salario', spending_type: 'fixed' }), ToolInputError);
  const dry = await pact(q, 'merge_categories', { from_id: 'mercado', into_id: 'moradia', dry_run: true });
  assert.deepEqual([dry.transactions, dry.budget], [1, 'o orçamento passa para a categoria de destino']);
  assert.equal(q.items.length, 2, 'a dry run queues nothing');
  await assert.rejects(pact(q, 'merge_categories', { from_id: 'mercado', into_id: 'salario' }), /mesmo tipo/);
  await pact(q, 'merge_categories', { from_id: 'mercado', into_id: 'moradia' });
  assert.deepEqual(q.items[2].args, { from_id: 'mercado', into_id: 'moradia' });
});

await test('parity: batch changes need a preview with a filter; transfers stay out', async () => {
  const q = smartQueue();
  const dry = await pact(q, 'update_transactions', { from: '2026-10-01', to: '2026-10-31', account_id: 'nu', set: { category_id: 'roupas' }, dry_run: true });
  assert.equal(dry.would_change, 4);
  assert.equal(q.items.length, 0);
  await assert.rejects(pact(q, 'update_transactions', { from: '2026-10-01', to: '2026-10-31', account_id: 'nu', set: { category_id: 'roupas' } }),
    /dry_run/);
  await assert.rejects(pact(q, 'update_transactions', { from: '2026-10-01', to: '2026-10-31', account_id: 'nu', set: { category_id: 'roupas' }, expected_count: 3 }),
    /agora pega 4/);
  await pact(q, 'update_transactions', { from: '2026-10-01', to: '2026-10-31', account_id: 'nu', set: { category_id: 'roupas' }, expected_count: 4 });
  assert.equal(q.items[0].kind, 'transaction.bulk_update');
  assert.deepEqual(q.items[0].args.ids.sort(), ['feira', 'ifood', 'ifood2', 'parcela']);
  // Ids need no preview; a category of the other type is refused.
  await pact(q, 'update_transactions', { ids: ['ifood', 'ifood2'], set: { subcategory: 'iFood', kind: 'extraordinary' } });
  assert.deepEqual(q.items[1].args, { ids: ['ifood', 'ifood2'], category_id: undefined, subcategory: 'iFood', expense_class: 'extraordinary' });
  await assert.rejects(pact(q, 'update_transactions', { ids: ['ifood', 'salario-out'], set: { category_id: 'roupas' } }), /tipo diferente/);
  const all = await pact(q, 'update_transactions', { from: '2026-10-01', to: '2026-10-31', set: { kind: 'normal' }, dry_run: true });
  assert.equal(all.skipped.count, 1, 'the transfer to the reserve is never batch-edited');
  await assert.rejects(pact(q, 'update_transactions', { ids: ['ifood'], from: '2026-10-01', set: { kind: 'normal' } }), /ids ou filtro/);
  await assert.rejects(pact(q, 'update_transactions', { set: { kind: 'normal' } }), /filtro/);
});

await test('parity: old adjustments become neutral; batch delete previews first', async () => {
  const q = smartQueue();
  const dry = await pact(q, 'convert_to_balance_adjustment', { category_id: 'ajuste', dry_run: true });
  assert.deepEqual([dry.would_change, dry.total], [1, 67.26]);
  await pact(q, 'convert_to_balance_adjustment', { category_id: 'ajuste', expected_count: 1 });
  assert.deepEqual(q.items[0], { id: q.items[0].id, kind: 'transaction.neutralize', key: undefined, status: 'pending', args: { ids: ['acerto-antigo'] } });
  await assert.rejects(pact(q, 'convert_to_balance_adjustment', { ids: ['luz-pendente'] }), /pendente/);
  const del = await pact(q, 'delete_transactions', { search: 'ifood', dry_run: true });
  assert.equal(del.would_change, 2);
  await pact(q, 'delete_transactions', { ids: ['ifood2'] });
  assert.deepEqual(q.items[1].args, { ids: ['ifood2'] });
  assert.equal((await pact(q, 'convert_to_balance_adjustment', { ids: ['reserva'], dry_run: true })).would_change, 0, 'a transfer is not converted');
});

await test('parity: split, duplicate and full edit of an entry', async () => {
  const q = smartQueue();
  const s = await pact(q, 'split_transaction', { id: 'camisa', installments: 3 });
  assert.deepEqual([s.first, s.each], [413.34, 413.33]);
  assert.deepEqual(q.items[0].args, { id: 'camisa', installments: 3 });
  await assert.rejects(pact(q, 'split_transaction', { id: 'parcela', installments: 2 }), /já é uma parcela/);
  await assert.rejects(pact(q, 'split_transaction', { id: 'reserva', installments: 2 }), ToolInputError);
  await pact(q, 'duplicate_transaction', { id: 'chopp', date: '2026-10-29' });
  assert.deepEqual(q.items[1], { id: q.items[1].id, kind: 'transaction.add', key: undefined, status: 'pending',
    args: { type: 'expense', amount_cents: 6000, description: 'chopp', account_id: 'main', category_id: 'bar', date: '2026-10-29', note: '' } });
  // Old fields keep the old kind (older apps understand it).
  await pact(q, 'update_transaction', { id: 'chopp', amount: 65 });
  assert.equal(q.items[2].kind, 'transaction.update');
  await pact(q, 'update_transaction', { id: 'luz-pendente', status: 'paid', subcategory: 'Energia', due_date: null });
  assert.deepEqual([q.items[3].kind, q.items[3].args], ['transaction.edit', { id: 'luz-pendente', status: 'paid', subcategory: 'Energia', due_date: null }]);
  await pact(q, 'update_transaction', { id: 'salario-out', recurring_income_id: 'sal' });
  assert.equal(q.items[4].args.recurring_income_id, 'sal');
  await assert.rejects(pact(q, 'update_transaction', { id: 'chopp', type: 'income' }), /receita|despesa/);
  await pact(q, 'update_transaction', { id: 'chopp', type: 'income', category_id: 'salario' });
  assert.deepEqual(q.items[5].args, { id: 'chopp', type: 'income', category_id: 'salario' });
  await assert.rejects(pact(q, 'update_transaction', { id: 'chopp', recurring_income_id: 'sal' }), /receita/);
  await assert.rejects(pact(q, 'update_transaction', { id: 'reserva', amount: 50 }), /transferência/);
});

await test('parity: undo, request list and status without the undo data', async () => {
  const q = smartQueue();
  const { request_id } = await pact(q, 'add_asset', { name: 'Bike', value: 900 });
  await assert.rejects(pact(q, 'undo_request', { id: request_id }), /ainda não foi gravado/);
  q.items[0].status = 'done';
  q.items[0].result = { asset_id: 'x', message: 'Bem cadastrado.', undo: { format: 1, entities: [], balances: [] } };
  const status = await pact(q, 'get_request_status', { id: request_id });
  assert.equal(status.undoable, true);
  assert.equal(status.result.undo, undefined, 'the undo data stays on the server');
  assert.equal(status.result.message, 'Bem cadastrado.');
  const r = await pact(q, 'undo_request', { id: request_id });
  assert.equal(q.items[1].kind, 'request.undo');
  assert.deepEqual(q.items[1].args, { request_id, undo: q.items[0].result.undo });
  assert.equal(r.status, 'pendente');
  q.items[0].result.undone_at = '2026-10-29T13:00:00Z';
  assert.match((await pact(q, 'get_request_status', { id: request_id })).status, /desfeito/);
  await assert.rejects(pact(q, 'undo_request', { id: request_id }), /já foi desfeito/);
  q.items.push({ id: '00000000-0000-4000-8000-000000000099', kind: 'transaction.add', status: 'done', result: { message: 'ok' } });
  await assert.rejects(pact(q, 'undo_request', { id: '00000000-0000-4000-8000-000000000099' }), /versão anterior/);
  q.items.push({ id: '00000000-0000-4000-8000-000000000098', kind: 'transaction.add', status: 'rejected', result: { reason: 'x' } });
  await assert.rejects(pact(q, 'undo_request', { id: '00000000-0000-4000-8000-000000000098' }), /recusado/);
  const list = await pact(q, 'list_requests', { limit: 10 });
  assert.equal(list.requests.find((x) => x.id === request_id).status, 'desfeito');
});

await test('parity: idempotency key, retried calls and ids of what is being created', async () => {
  const q = smartQueue();
  const first = await pact(q, 'add_transaction', { type: 'expense', amount: 5, description: 'Café', account_id: 'main', category_id: 'bar', idempotency_key: 'cafe-29' });
  const again = await pact(q, 'add_transaction', { type: 'expense', amount: 5, description: 'Café', account_id: 'main', category_id: 'bar', idempotency_key: 'cafe-29' });
  assert.equal(again.request_id, first.request_id);
  assert.equal(again.deduplicated, true);
  assert.match(again.message, /nada foi duplicado/);
  assert.equal(q.items.length, 1);
  assert.deepEqual(q.keys, ['cafe-29', 'cafe-29']);
  assert.equal(first.new_id, `assistant:${first.request_id}`);
  assert.equal(q.items[0].args.idempotency_key, undefined, 'the key never reaches the app');
  await assert.rejects(pact(q, 'add_transaction', { type: 'expense', amount: 5, description: 'x', account_id: 'main', category_id: 'bar', idempotency_key: '' }), ToolInputError);
  // A category created a moment ago can be used before the app records it.
  const cat = await pact(q, 'add_category', { name: 'Pets', type: 'expense' });
  assert.equal(cat.new_id, `assistant-cat:${cat.request_id}`);
  await pact(q, 'add_transaction', { type: 'expense', amount: 30, description: 'Ração', account_id: 'main', category_id: cat.new_id });
  assert.equal(q.items.at(-1).args.category_id, cat.new_id);
  await pact(q, 'set_category_type', { assignments: [{ category_id: cat.new_id, type: 'comfort' }] });
  q.items.find((x) => x.id === cat.request_id).status = 'rejected';
  await assert.rejects(pact(q, 'add_transaction', { type: 'expense', amount: 31, description: 'Ração', account_id: 'main', category_id: cat.new_id }), /Categoria não encontrada/);
  await assert.rejects(pact(q, 'add_transaction', { type: 'expense', amount: 31, description: 'x', account_id: 'main', category_id: 'assistant-cat:00000000-0000-4000-8000-00000000abcd' }), ToolInputError);
});

await test('parity: budgets in full or proportional, with the shared week start', async () => {
  const q = smartQueue();
  const b = Object.fromEntries((await pact(q, 'get_budgets', {})).budgets.map((x) => [x.id, x]));
  // Created on 21/10 for R$ 400: 11 of 31 days, proportional.
  assert.deepEqual([b['b-mercado'].limit, b['b-mercado'].full_limit, b['b-mercado'].prorated, b['b-mercado'].counts_from],
    [141.94, 400, true, '2026-10-21']);
  assert.equal(b['b-bar'].prorated, false);
  assert.equal((await pact(q, 'get_budgets', {})).week_starts_on, 'segunda');
  const sunday = { ...scenario, sharedSettings: [...scenario.sharedSettings, { key: 'weekStart', value: '"sunday"' }] };
  assert.equal((await pact(q, 'get_budgets', {}, sunday)).week_starts_on, 'domingo');
  await pact(q, 'update_budget', { id: 'b-mercado', full_period: true });
  assert.deepEqual(q.items[0], { id: q.items[0].id, kind: 'budget.save', key: undefined, status: 'pending',
    args: { id: 'b-mercado', category_id: 'mercado', period: 'monthly', amount_cents: 40000, full_period: true } });
  await pact(q, 'set_budget', { category_id: 'delivery', amount: 150, full_period: true });
  assert.deepEqual([q.items[1].kind, q.items[1].args.full_period], ['budget.save', true]);
  await pact(q, 'set_budget', { category_id: 'delivery', amount: 160 });
  assert.equal(q.items[2].kind, 'budget.set', 'without the flag, the older request');
  await assert.rejects(pact(q, 'update_budget', { id: 'b-mercado' }), ToolInputError);
});

await test('parity: goals only on paper, recurring details, card details', async () => {
  const q = smartQueue();
  const r = await pact(q, 'move_goal', { goal_id: 'trip', amount: 100, direction: 'withdraw', move_money: false });
  assert.deepEqual(q.items[0], { id: q.items[0].id, kind: 'goal.adjust', key: undefined, status: 'pending',
    args: { goal_id: 'trip', amount_cents: 10000, direction: 'withdraw', note: '' } });
  assert.match(r.note, /nenhuma conta/);
  await assert.rejects(pact(q, 'move_goal', { goal_id: 'trip', amount: 500, direction: 'withdraw', move_money: false }), /supera/);
  await assert.rejects(pact(q, 'move_goal', { goal_id: 'trip', amount: 50, direction: 'withdraw' }), /account_id/);
  await pact(q, 'update_goal', { id: 'trip', completed: true, color: '#AB47BC' });
  assert.deepEqual(q.items[1].args, { id: 'trip', completed: true, color: 0xFFAB47BC });
  await pact(q, 'update_goal', { id: 'trip', target: 1200 });
  assert.equal(q.items[2].kind, 'goal.update');
  await pact(q, 'update_recurring', { id: 'net', frequency: 'yearly', notes: 'plano anual', end_date: null });
  assert.deepEqual([q.items[3].kind, q.items[3].args], ['recurring.edit', { id: 'net', end_date: null, freq_unit: 'years', notes: 'plano anual' }]);
  await assert.rejects(pact(q, 'update_recurring', { id: 'net', kind: 'installment' }), /end_date/);
  await pact(q, 'update_recurring', { id: 'net', amount: 109.9 });
  assert.equal(q.items[4].kind, 'recurring.update');
  await pact(q, 'update_account', { id: 'nu', payment_account_id: 'main', min_payment: 65, reminder_enabled: true });
  assert.deepEqual([q.items[5].kind, q.items[5].args], ['account.edit', { id: 'nu', min_payment_cents: 6500, linked_account_id: 'main', reminder_enabled: true }]);
  await pact(q, 'update_account', { id: 'nu', credit_limit: null });
  assert.deepEqual(q.items[6].args, { id: 'nu', credit_limit_cents: null });
  await assert.rejects(pact(q, 'update_account', { id: 'main', due_day: 10, exclude_from_bank_total: true }), /cartão/);
  await assert.rejects(pact(q, 'update_account', { id: 'nu', payment_account_id: 'nu' }), ToolInputError);
  await pact(q, 'update_account', { id: 'nu', statement_day: 19 });
  assert.equal(q.items.at(-1).kind, 'account.update', 'the older request when it is enough');
});

await test('parity: the Nubank-like invoice with its own statement', async () => {
  const q = smartQueue();
  const card = (await pact(q, 'get_card_invoices', { card_id: 'nu', include_transactions: true })).cards[0];
  const [nov, oct] = card.invoices;
  // A purchase on the closing day (19/10) belongs to the next invoice.
  assert.deepEqual(oct.transactions.map((t) => [t.id, t.kind]), [['feira', 'compra'], ['parcela', 'compra'], ['pay-set', 'pagamento']]);
  assert.equal(oct.transactions.find((t) => t.id === 'parcela').installment, '1/3');
  assert.deepEqual(nov.transactions.map((t) => t.id), ['ifood', 'ifood2']);
  assert.deepEqual([oct.total, oct.paid, oct.remaining, oct.due_date], [170.5, 100, 70.5, '2026-10-26']);
  assert.equal((await pact(q, 'get_card_invoices', { card_id: 'nu' })).cards[0].invoices[0].transactions, undefined);
});

await test('parity: investments, loans, people, rules and Open Finance', async () => {
  const q = smartQueue();
  const inv = (await pact(q, 'get_investments', {})).investments[0];
  assert.deepEqual(inv.operations.map((o) => [o.id, o.cash_account_id]), [['op-old', undefined], ['op-buy', 'main']]);
  await assert.rejects(pact(q, 'archive_investment', { id: 'petr' }), /Encerre/);
  await pact(q, 'archive_investment', { id: 'petr', archived: false });
  await pact(q, 'delete_investment_operation', { operation_id: 'op-buy' });
  await assert.rejects(pact(q, 'link_investment_operation', { operation_id: 'op-buy', account_id: 'main' }), /já movimenta/);
  await pact(q, 'link_investment_operation', { operation_id: 'op-old', account_id: 'main' });
  await assert.rejects(pact(q, 'link_investment_operation', { operation_id: 'op-old', account_id: 'nu' }), /cartão/);
  assert.deepEqual(q.items.map((x) => x.kind), ['investment.archive', 'investment.unrecord', 'investment.link']);

  const loans = (await pact(q, 'get_loans', {})).loans;
  assert.deepEqual(loans[0].payment_list.map((p) => p.id), ['lp1']);
  await pact(q, 'add_loan', { name: 'Notebook', principal: 3000, start_date: '2026-11-01', end_date: '2027-11-01', interest_rate: 12, account_id: 'main' });
  assert.deepEqual(q.items.at(-1).args, { name: 'Notebook', principal_cents: 300000, start_date: '2026-11-01', end_date: '2027-11-01', interest_rate: 12, account_id: 'main' });
  await assert.rejects(pact(q, 'add_loan', { name: 'X', principal: 1, start_date: '2027-01-01', end_date: '2026-01-01' }), /depois/);
  await pact(q, 'update_loan', { id: 'carro', account_id: null, settled: true });
  assert.deepEqual(q.items.at(-1).args, { id: 'carro', account_id: null, settled: true });
  await pact(q, 'delete_loan_payment', { payment_id: 'lp1' });
  await pact(q, 'delete_loan', { id: 'carro' });

  const lended = await pact(q, 'get_lended', {});
  assert.deepEqual(lended.people.map((p) => p.id), ['ana', 'bia']);
  await pact(q, 'update_lended', { id: 'len', amount: 60, due_date: null });
  assert.deepEqual(q.items.at(-1).args, { id: 'len', amount_cents: 6000, due_date: null });
  await assert.rejects(pact(q, 'delete_person', { id: 'ana' }), /em aberto/);
  await pact(q, 'delete_person', { id: 'bia' });
  await pact(q, 'update_person', { id: 'ana', name: 'Ana fictícia' });
  await pact(q, 'delete_lended', { id: 'len' });

  const rules = await pact(q, 'get_import_rules', {});
  assert.deepEqual(rules.rules.map((r) => [r.pattern, r.category]), [['IFOOD', 'Delivery']]);
  await pact(q, 'save_import_rule', { pattern: 'UBER', category_id: 'delivery' });
  assert.deepEqual(q.items.at(-1).args, { pattern: 'UBER', type: 'expense', category_id: 'delivery', subcategory: '' });
  await pact(q, 'delete_import_rule', { id: 'r-ifood' });
  await assert.rejects(pact(q, 'delete_import_rule', { id: 'nope' }), ToolInputError);

  await pact(q, 'confirm_suggestion', { id: 'pluggy:a', account_id: 'nu', category_id: 'delivery', subcategory: 'iFood' });
  assert.deepEqual([q.items.at(-1).kind, q.items.at(-1).args.subcategory], ['suggestion.accept', 'iFood']);
  await pact(q, 'confirm_suggestion', { id: 'pluggy:a', account_id: 'nu', category_id: 'delivery' });
  assert.equal(q.items.at(-1).kind, 'suggestion.confirm', 'the older request when it is enough');
  await pact(q, 'confirm_suggestion_as_transfer', { id: 'pluggy:b', from_account_id: 'main', to_account_id: 'nu' });
  assert.equal(q.items.at(-1).kind, 'suggestion.transfer');
  await pact(q, 'refresh_bank_data', {});
  assert.equal(q.items.at(-1).kind, 'bank.refresh');
});

await test('parity: trend, net worth, cash projection and grouped spending', async () => {
  const q = smartQueue();
  const trend = await pact(q, 'get_monthly_trend', { months: 2 });
  assert.deepEqual(trend.months.map((m) => [m.month, m.partial]), [['2026-09', false], ['2026-10', true]]);
  assert.equal(trend.months[1].income, 1867.26, 'the old adjustment still counts as income until converted');
  assert.equal(trend.average_spending, 999);
  const nw = await pact(q, 'get_net_worth', {});
  assert.deepEqual([nw.accounts, nw.card_debt, nw.investments, nw.assets, nw.loans_outstanding, nw.lent_to_others],
    [2000, -300, 600, 8000, -9100, 50]);
  assert.equal(nw.net_worth, 2000 - 300 + 600 + 8000 - 9100 + 50);
  const cash = await pact(q, 'get_cash_projection', { until: '2026-11-30' });
  assert.equal(cash.starting_cash, 2000);
  const whats = cash.timeline.map((t) => t.what);
  assert(whats.some((w) => w.startsWith('Fatura Nubank')), 'the closed invoice due on 26/11 or earlier');
  assert(whats.includes('luz-pendente (pendente)'));
  assert(whats.includes('Salário (recorrente)'));
  assert(!whats.some((w) => w.startsWith('Spotify')), 'card subscriptions arrive through the invoice');
  await assert.rejects(pact(q, 'get_cash_projection', { until: '2026-10-01' }), ToolInputError);
  const byType = await pact(q, 'get_spending_breakdown', { from: '2026-10-01', to: '2026-10-31', by: 'spending_type' });
  assert.equal(byType.groups.find((g) => g.group === 'Sem tipo').amount, 1370.28);
  const byDay = await pact(q, 'get_spending_breakdown', { from: '2026-10-01', to: '2026-10-31', by: 'weekday' });
  assert.equal(byDay.total, byType.total);
  assert.equal(byType.total, callTool('get_spending_by_category', { from: '2026-10-01', to: '2026-10-31' }, scenario, tday).total,
    'same rule as the screens: grouping never changes the total');
});

await test('parity: catalog, keys on every change tool, mirrors of the app lists', async () => {
  const q = smartQueue();
  const cat = await pact(q, 'describe_app_capabilities', {});
  const named = new Set(Object.values(cat.entities).flatMap((e) => [...(e.read ?? []), ...(e.write ?? [])]));
  const listed = new Set([...tools.map((t) => t.name), ...actions.map((t) => t.name)]);
  for (const n of named) assert(listed.has(n), `catalog names a tool that does not exist: ${n}`);
  for (const n of listed) assert(named.has(n), `tool missing from the catalog: ${n}`);
  assert.equal(cat.devices[0].app_version, '1.13.0+52');
  const handler = createHandler({
    authenticate: async t => (t === token ? { id: 'c1', ownerId: 'u1', datasetId: 'd1' } : null),
    load: async () => scenario, audit: async () => {}, today: () => tday, actions: () => smartQueue().deps,
  });
  const res = await (await handler(new Request('https://x.supabase.co/functions/v1/nexo-mcp', {
    method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify(rpcCall('tools/list', {})),
  }))).json();
  for (const t of res.result.tools) {
    const key = t.inputSchema.properties?.idempotency_key;
    if (t.annotations.readOnlyHint) assert.equal(key, undefined, t.name);
    else assert.ok(key, `${t.name} accepts idempotency_key`);
  }
  for (const n of ['get_spending_types', 'get_settings', 'describe_app_capabilities', 'get_net_worth']) assert(readOnlyActions.has(n), n);
  for (const n of ['delete_transactions', 'merge_categories', 'undo_request']) {
    assert.equal(res.result.tools.find((t) => t.name === n).annotations.destructiveHint, true, n);
  }
  assert.match(instructions, /describe_app_capabilities/);
  assert.match(instructions, /undo_request/);
  // The server mirrors lists of the app; drift fails here.
  const dartSettings = await readFile(new URL('../lib/sync/assistant_settings.dart', import.meta.url), 'utf8');
  const dartKeys = [...dartSettings.matchAll(/AssistantSetting\(\s*'([a-zA-Z]+)'/g)].map((m) => m[1]);
  assert.deepEqual(settingDefs.map((d) => d.key), dartKeys);
  const entries = dartSettings.split('final assistantSettings')[1].split('AssistantSetting(').slice(1);
  const dartShared = entries.filter((e) => e.includes('shared: true')).map((e) => e.match(/'([a-zA-Z]+)'/)[1]);
  assert.deepEqual(settingDefs.filter((d) => d.shared).map((d) => d.key), dartShared);
  const dartEnvelopes = await readFile(new URL('../lib/services/envelopes.dart', import.meta.url), 'utf8');
  const defs = [...dartEnvelopes.matchAll(/EnvelopeDef\(\s*'([a-z]+)',\s*'([^']+)',\s*(\d+),/g)].map((m) => [m[1], m[2], Number(m[3])]);
  assert.deepEqual(envelopes.map((e) => [e.id, e.name, e.defaultShare]), defs);
  const dartIcons = await readFile(new URL('../lib/widgets/shared_widgets.dart', import.meta.url), 'utf8');
  const iconBlock = dartIcons.split('kCategoryIconOptions = [')[1].split('];')[0];
  assert.deepEqual(categoryIcons, [...iconBlock.matchAll(/CategoryIconOption\(Icons\.[a-z_]+, '([^']+)'\)/g)].map((m) => m[1]));
  // Every kind the server can queue is one the app applies.
  const dartKinds = (await readFile(new URL('../lib/sync/assistant_commands.dart', import.meta.url), 'utf8')) +
    (await readFile(new URL('../lib/sync/assistant_parity_commands.dart', import.meta.url), 'utf8'));
  const appKinds = new Set([...dartKinds.matchAll(/'([a-z]+\.[a-z_]+)'/g)].map((m) => m[1]));
  const sources = await Promise.all(['actions', 'more_actions', 'all_actions', 'parity_actions'].map((f) =>
    readFile(new URL(`../supabase/functions/nexo-mcp/${f}.ts`, import.meta.url), 'utf8')));
  const queued = new Set(sources.flatMap((src) => [...src.matchAll(/"([a-z]+\.[a-z_]+)"/g)].map((m) => m[1]))
    .filter((k) => !k.endsWith('.ts')));
  for (const kind of queued) assert(appKinds.has(kind), `the app does not apply ${kind}`);
  assert(queued.size >= 60, `kinds found: ${queued.size}`);
  for (const kind of Object.keys(createdIdPrefix)) assert(appKinds.has(kind), kind);
  void parityActions;
});

await test('parity: creating like the form, and the bank side by side with the Nexo', async () => {
  const q = smartQueue();
  await pact(q, 'add_transaction', { type: 'expense', amount: 1200, description: 'Notebook', account_id: 'nu', category_id: 'roupas', installments: 10 });
  assert.deepEqual([q.items[0].kind, q.items[0].args.installments], ['transaction.create', 10]);
  await pact(q, 'add_transaction', { type: 'expense', amount: 90, description: 'Água', account_id: 'main', category_id: 'moradia', status: 'pending', due_date: '2026-11-10', subcategory: 'Água' });
  assert.deepEqual(q.items[1].args, { type: 'expense', amount_cents: 9000, description: 'Água', account_id: 'main', category_id: 'moradia',
    date: tday, note: '', subcategory: 'Água', status: 'pending', due_date: '2026-11-10' });
  await pact(q, 'add_transaction', { type: 'expense', amount: 9, description: 'Café', account_id: 'main', category_id: 'bar' });
  assert.equal(q.items[2].kind, 'transaction.add', 'the older request when it is enough');
  await assert.rejects(pact(q, 'add_transaction', { type: 'expense', amount: 9, description: 'x', account_id: 'main', category_id: 'bar', installments: 1 }), ToolInputError);

  q.deps.bankAccounts = async () => [
    { account_id: 'acc-1', bank: 'Banco A', type: 'BANK', name: 'Corrente', balance_cents: 150000, nexo_account_id: 'main', bills: [] },
    { account_id: 'acc-2', bank: 'Banco B', type: 'BANK', name: 'Conta 2', balance_cents: 50000, nexo_account_id: 'main', bills: [] },
    { account_id: 'acc-3', bank: 'Banco A', type: 'CREDIT', name: 'Cartão', balance_cents: 30000, credit_limit_cents: 65000,
      available_cents: 35000, nexo_account_id: 'nu', bills: [{ due_date: '2026-10-26', total_cents: 17050, paid_cents: 10000, minimum_cents: 1700 }] },
    { account_id: 'acc-4', bank: 'Banco C', type: 'BANK', name: 'Sem vínculo', balance_cents: 100, nexo_account_id: null, bills: [] },
  ];
  q.linked = [];
  q.deps.linkBankAccount = async (id, nexo) => { q.linked.push([id, nexo]); return id === 'acc-4' ? 1 : 0; };
  const bank = await pact(q, 'get_bank_accounts', {});
  const main = bank.check.find((c) => c.nexo_account_id === 'main');
  assert.deepEqual([main.bank, main.nexo, main.difference], [2000, 2000, 0], 'two bank accounts summed into one');
  const card = bank.check.find((c) => c.nexo_account_id === 'nu');
  assert.deepEqual([card.bank, card.nexo, card.difference], [-300, -300, 0], 'what a card owes is negative in the Nexo');
  assert.deepEqual(bank.accounts.find((a) => a.account_id === 'acc-3').official_invoices[0], { due_date: '2026-10-26', total: 170.5, paid: 100, minimum: 17 });
  const linked = await pact(q, 'link_bank_account', { account_id: 'acc-4', nexo_account_id: 'main' });
  assert.equal(linked.linked, true);
  await pact(q, 'link_bank_account', { account_id: 'acc-4', nexo_account_id: null });
  assert.deepEqual(q.linked, [['acc-4', 'main'], ['acc-4', null]]);
  await assert.rejects(pact(q, 'link_bank_account', { account_id: 'acc-9', nexo_account_id: 'main' }), /não encontrada/);
  await assert.rejects(pact(q, 'link_bank_account', { account_id: 'acc-4', nexo_account_id: 'nope' }), ToolInputError);
  const old = smartQueue();
  assert.deepEqual((await pact(old, 'get_bank_accounts', {})).accounts, []);
});

console.log(`NEXO MCP: ${passed} tests passed; synthetic fixture only.`);
