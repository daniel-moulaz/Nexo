// Local PostgreSQL/WASM tests. No network, no credentials, no production DB.
// npm install --prefix build/sync-sql-runtime --ignore-scripts --save-exact @electric-sql/pglite@0.5.10
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash, randomUUID } from 'node:crypto';
import { PGlite } from '../build/sync-sql-runtime/node_modules/@electric-sql/pglite/dist/index.js';

const db = new PGlite();
const A = '11111111-1111-4111-8111-111111111111';
const B = '22222222-2222-4222-8222-222222222222';
const dataset = randomUUID(), epoch = randomUUID(), phone = randomUUID(), pc = randomUUID();
let passed = 0;
const canonical = value => JSON.stringify(sort(value));
function sort(value) {
  if (Array.isArray(value)) return value.map(sort);
  if (value && typeof value === 'object') return Object.fromEntries(
    Object.keys(value).sort().map(k => [k, sort(value[k])]));
  return value;
}
function op(edits, extra = {}) {
  return { protocol: 1, id: randomUUID(), dataset_id: dataset, epoch,
    device_id: phone, created_at: '2026-10-16T12:00:00.000Z', edits, ...extra };
}
const edit = (id, base, value, kind = 'account') =>
  ({ id, kind, base_revision: base, value });
const hash = payload => createHash('sha256').update(payload).digest('hex');
async function user(id, action, role = 'authenticated') {
  return db.transaction(async tx => {
    await tx.exec(`set local role ${role}`); // role is a test constant only.
    await tx.query("select set_config('request.jwt.claim.sub', $1, true)", [id ?? '']);
    return action(tx);
  });
}
async function rpc(tx, name, args) {
  const result = await tx.query(`select public.${name}(${args.map((_, i) => `$${i + 1}`).join(',')}) as result`, args);
  return result.rows[0].result;
}
const create = (tx, device = phone, ds = dataset, ep = epoch, synthetic = true) =>
  rpc(tx, 'nexo_sync_lab_create', [ds, ep, device, synthetic]);
const push = (tx, operation) => {
  const payload = canonical(operation);
  return rpc(tx, 'nexo_sync_lab_push', [payload, hash(payload)]);
};
const pull = (tx, after = 0, device = phone, ds = dataset, ep = epoch, limit = 100) =>
  rpc(tx, 'nexo_sync_lab_pull', [ds, ep, device, after, limit]);
async function denies(action, code) {
  await assert.rejects(action, error => !code || error.code === code);
}
async function test(name, action) {
  await action();
  passed++;
  console.log(`PASS ${name}`);
}

try {
  await db.exec(`create role anon nologin; create role authenticated nologin;
    create role service_role nologin bypassrls;
    create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema auth to anon, authenticated;
    grant execute on function auth.uid() to anon, authenticated;`);
  await db.exec(await readFile(new URL('../supabase/migrations/202610160001_sync_lab.sql', import.meta.url), 'utf8'));
  // Every protocol-1 test below runs against the protocol-2 function.
  await db.exec(await readFile(new URL('../supabase/migrations/202610200001_sync_protocol_v2.sql', import.meta.url), 'utf8'));
  await db.exec(await readFile(new URL('../supabase/migrations/202610200002_mcp_connectors.sql', import.meta.url), 'utf8'));
  await test('remote smoke script passes and rolls back all synthetic rows', async () => {
    const results = await db.exec(await readFile(new URL('../supabase/tests/sync_lab_smoke.sql', import.meta.url), 'utf8'));
    const row = results.at(-1).rows[0];
    assert.equal(row.validation, 'synthetic_smoke_passed');
    assert.equal(row.persisted_datasets, 0);
    assert.equal(row.persisted_entities, 0);
    assert.equal(row.persisted_requests, 0);
    assert.equal(row.all_rls_enabled, true);
    assert.equal(row.anonymous_blocked, true);
  });
  await test('protocol 2 remote smoke script passes and rolls back', async () => {
    const results = await db.exec(await readFile(new URL('../supabase/tests/sync_protocol_v2_smoke.sql', import.meta.url), 'utf8'));
    const row = results.at(-1).rows[0];
    assert.equal(row.validation, 'synthetic_v2_smoke_passed');
    assert.equal(row.persisted_datasets, 0);
    assert.equal(row.persisted_balances, 0);
    assert.equal(row.all_rls_enabled, true);
  });
  await test('all private tables have RLS and no direct client write access', async () => {
    const rows = (await db.query(`select relname, relrowsecurity from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'nexo_sync_lab_private' and relkind = 'r'`)).rows;
    assert.equal(rows.length, 5); // sync lab tables; MCP tables checked below
    assert(rows.every(r => r.relrowsecurity));
    await denies(() => user(A, tx => tx.query('select * from nexo_sync_lab_private.datasets')), '42501');
  });
  await test('all four RPCs deny anonymous execution', async () => {
    for (const call of [tx => create(tx), tx => push(tx, op([edit('a', 0, {})])),
      tx => pull(tx), tx => rpc(tx, 'nexo_sync_lab_revoke_device', [dataset, phone])]) {
      await denies(() => user(null, call, 'anon'), '42501');
    }
  });
  await test('authenticated role without user identity cannot create datasets', () =>
    denies(() => user(null, tx => create(tx)), '42501'));
  await test('explicit synthetic flag required', () =>
    denies(() => user(A, tx => create(tx, phone, dataset, epoch, false)), '22023'));
  await test('create is idempotent for owner and permits another device', async () => {
    assert.equal((await user(A, tx => create(tx))).revision, 0);
    assert.equal((await user(A, tx => create(tx))).revision, 0);
    await user(A, tx => create(tx, pc));
  });
  await test('other user cannot attach to, pull, revoke or push owner dataset', async () => {
    for (const call of [tx => create(tx), tx => pull(tx),
      tx => push(tx, op([edit('a', 0, {})])),
      tx => rpc(tx, 'nexo_sync_lab_revoke_device', [dataset, phone])]) {
      await denies(() => user(B, call), '42501');
    }
  });
  const opening = op([edit('bank', 0, { balance: 1000, name: 'Banco fictício' }),
    edit('reserve', 0, { balance: 0 })]);
  await test('one committed revision for an atomic multi-entity aggregate', async () => {
    const result = await user(A, tx => push(tx, opening));
    assert.equal(result.revision, 1);
    assert.equal(result.hash, hash(canonical(opening)));
    assert.equal(result.payload, canonical(opening));
  });
  await test('retry returns original receipt and changes no balance', async () => {
    const first = await user(A, tx => push(tx, opening));
    assert.deepEqual(await user(A, tx => push(tx, opening)), first);
    assert.equal((await user(A, tx => pull(tx))).length, 1);
  });
  await test('ID reused with different payload is rejected', () =>
    denies(() => user(A, tx => push(tx, { ...opening, edits: [edit('bank', 0, { balance: 9999 })] })), '22023'));
  await test('hash mismatch and malformed JSON are rejected', async () => {
    await denies(() => user(A, tx => rpc(tx, 'nexo_sync_lab_push', [canonical(opening), '0'.repeat(64)])), '22023');
    await denies(() => user(A, tx => rpc(tx, 'nexo_sync_lab_push', ['{', hash('{')])), '22023');
  });
  await test('invalid protocol, identifiers, revisions, batch and value fail closed', async () => {
    const malformed = [
      { ...opening, protocol: 2 }, { ...opening, dataset_id: null },
      { ...opening, epoch: 'invalid' }, { ...opening, created_at: 'infinity' },
      op([]), op([edit('a', -1, {})]), op([edit('a', 0, null)]),
      op([edit('a', 1.5, {})]), op([edit('a', 0, [])]),
      op([edit('a', 0, {}), edit('a', 0, {})]),
      op([edit('', 0, {})]), op([{ kind: 'account', id: 'a', base_revision: 0 }]),
    ];
    for (const item of malformed) await denies(() => user(A, tx => push(tx, item)), '22023');
    assert.equal((await user(A, tx => pull(tx))).length, 1);
  });
  await test('payload size is bounded', async () => {
    const large = canonical(op([edit('big', 0, { text: 'x'.repeat(1048576) })]));
    await denies(() => user(A, tx => rpc(tx, 'nexo_sync_lab_push', [large, hash(large)])), '22023');
  });
  const transfer = op([edit('bank', 1, { balance: 800 }), edit('reserve', 1, { balance: 200 }),
    edit('pair', 0, { out: 200, in: 200, neutral: true }, 'transfer')]);
  await test('transfer commits both sides with a single cursor', async () => {
    assert.equal((await user(A, tx => push(tx, transfer))).revision, 2);
    const rows = (await db.query(`select id, value from nexo_sync_lab_private.entities
      where dataset_id = $1 and kind = 'account' order by id`, [dataset])).rows;
    assert.equal(rows.reduce((total, r) => total + r.value.balance, 0), 1000);
  });
  const stale = op([edit('bank', 1, { balance: 900 }), edit('new', 0, { amount: 100 }, 'transaction')], { device_id: pc });
  await test('concurrent financial edit returns complete alternatives without partial writes', async () => {
    const result = await user(A, tx => push(tx, stale));
    assert.equal(result.status, 'conflict');
    assert.equal(result.remote.length, 2);
    assert.equal(result.remote.find(r => r.id === 'bank').value.balance, 800);
    assert.equal(result.remote.find(r => r.id === 'new').revision, 0);
    assert.equal((await db.query('select count(*)::int as n from nexo_sync_lab_private.entities where id = $1', ['new'])).rows[0].n, 0);
    assert.deepEqual(await user(A, tx => push(tx, stale)), result);
  });
  await test('rejected IDs also cannot be reused with another payload', () =>
    denies(() => user(A, tx => push(tx, { ...stale, created_at: '2030-01-01T00:00:00.000Z' })), '22023'));
  await test('pagination includes accepted operations only, without cursor gaps', async () => {
    const first = await user(A, tx => pull(tx, 0, pc, dataset, epoch, 1));
    const next = await user(A, tx => pull(tx, first[0].revision, pc));
    assert.deepEqual([first[0].revision, ...next.map(r => r.revision)], [1, 2]);
    assert.deepEqual(await user(A, tx => pull(tx, 2)), []);
  });
  await test('unknown device, wrong epoch and invalid cursor are rejected', async () => {
    await denies(() => user(A, tx => pull(tx, 0, randomUUID())), '42501');
    await denies(() => user(A, tx => push(tx, op([edit('x', 0, {})], { device_id: randomUUID() }))), '42501');
    await denies(() => user(A, tx => pull(tx, 0, phone, dataset, randomUUID())), '22023');
    await denies(() => user(A, tx => pull(tx, 999)), '22023');
    await denies(() => user(A, tx => pull(tx, 0, phone, dataset, epoch, 101)), '22023');
  });
  await test('server error rolls back entities and dataset clock together', async () => {
    await db.exec(`create function nexo_sync_lab_private.fail_request() returns trigger
      language plpgsql as $$ begin raise exception 'synthetic failure'; end $$;
      create trigger fail_request before insert on nexo_sync_lab_private.requests
        for each row execute function nexo_sync_lab_private.fail_request();`);
    const operation = op([edit('bank', 2, { balance: 700 })]);
    await denies(() => user(A, tx => push(tx, operation)));
    assert.equal((await user(A, tx => pull(tx))).length, 2);
    await db.exec('drop trigger fail_request on nexo_sync_lab_private.requests');
    assert.equal((await user(A, tx => push(tx, operation))).revision, 3);
  });
  await test('tombstone blocks old creation and does not resurrect on retry', async () => {
    const creation = op([edit('old-budget', 0, { amount: 350 }, 'budget')]);
    await user(A, tx => push(tx, creation));
    await user(A, tx => push(tx, op([edit('old-budget', 1, null, 'budget')])));
    assert.equal((await user(A, tx => push(tx, op(creation.edits)))).status, 'conflict');
    await user(A, tx => push(tx, creation));
    const row = (await db.query("select revision, value, deleted_at from nexo_sync_lab_private.entities where kind = 'budget' and id = 'old-budget'")).rows[0];
    assert.equal(row.revision, 2);
    assert.equal(row.value, null);
    assert(row.deleted_at);
  });
  await test('revoked device cannot push, pull, re-register or replay receipts', async () => {
    await user(A, tx => rpc(tx, 'nexo_sync_lab_revoke_device', [dataset, phone]));
    for (const call of [tx => pull(tx), tx => create(tx), tx => push(tx, opening)]) {
      await denies(() => user(A, call), '42501');
    }
    assert((await user(A, tx => pull(tx, 0, pc))).length > 0);
  });
  await test('RLS filters all four tables even if a future SELECT grant is added', async () => {
    const otherDataset = randomUUID(), otherEpoch = randomUUID(), otherDevice = randomUUID();
    await user(B, tx => create(tx, otherDevice, otherDataset, otherEpoch));
    await user(B, tx => push(tx, op([edit('private-b', 0, {})], {
      dataset_id: otherDataset, epoch: otherEpoch, device_id: otherDevice })));
    await db.exec('grant usage on schema nexo_sync_lab_private to authenticated; grant select on all tables in schema nexo_sync_lab_private to authenticated;');
    for (const table of ['datasets', 'devices', 'entities', 'requests']) {
      for (const identity of [A, B]) {
        const rows = await user(identity, tx => tx.query(`select owner_id from nexo_sync_lab_private.${table}`));
        assert(rows.rows.length > 0);
        assert(rows.rows.every(r => r.owner_id === identity));
      }
    }
    await db.exec('revoke all on schema nexo_sync_lab_private from authenticated; revoke all on all tables in schema nexo_sync_lab_private from authenticated;');
  });
  // ── Protocol 2: effects, requirements and the balance projection ──────
  const ds2 = randomUUID(), ep2 = randomUUID(), d1 = randomUUID(), d2 = randomUUID();
  const op2 = (edits, effects = [], requires = [], device = d1, extra = {}) => ({
    protocol: 2, id: randomUUID(), dataset_id: ds2, epoch: ep2, device_id: device,
    created_at: '2026-10-20T12:00:00.000Z', edits, effects, requires,
    label: 'transaction.add', ...extra });
  const balance = async account => (await db.query(
    'select micros from nexo_sync_lab_private.balances where dataset_id = $1 and account_id = $2',
    [ds2, account])).rows[0]?.micros;
  const accountV = { name: 'Banco fictício', currency: 'BRL' };
  await test('v2 dataset bootstrap carries the opening balance as an effect', async () => {
    await user(A, tx => create(tx, d1, ds2, ep2));
    await user(A, tx => create(tx, d2, ds2, ep2));
    const opening = op2([edit('bank', 0, accountV, 'accounts')], [{ account: 'bank', delta_micros: 1000000000 }]);
    assert.equal((await user(A, tx => push(tx, opening))).status, 'accepted');
    assert.equal(BigInt(await balance('bank')), 1000000000n);
  });
  const spend = (id, micros, device) => op2(
    [edit(id, 0, { amount: micros / 1e6 }, 'transactions')],
    [{ account: 'bank', delta_micros: -micros }],
    [{ kind: 'accounts', id: 'bank', revision: 1 }], device);
  await test('independent spending from two devices on one account both commit', async () => {
    assert.equal((await user(A, tx => push(tx, spend('t1', 7500000, d1)))).status, 'accepted');
    assert.equal((await user(A, tx => push(tx, spend('t2', 300000, d2)))).status, 'accepted');
    assert.equal(BigInt(await balance('bank')), 992200000n);
  });
  await test('changed requirement rejects atomically with complete alternatives', async () => {
    const rename = op2([edit('bank', 1, { ...accountV, name: 'Outro' }, 'accounts')]);
    assert.equal((await user(A, tx => push(tx, rename))).status, 'accepted');
    const stale = spend('t3', 1000000, d2);
    const result = await user(A, tx => push(tx, stale));
    assert.equal(result.status, 'conflict');
    assert.equal(result.remote.length, 2);
    assert.equal(result.remote.find(r => r.id === 'bank').revision, 2);
    assert.equal(BigInt(await balance('bank')), 992200000n);
    assert.equal((await db.query("select count(*)::int as n from nexo_sync_lab_private.entities where id = 't3'")).rows[0].n, 0);
  });
  await test('effect-only operation is accepted; empty v2 operation is not', async () => {
    const adjust = op2([], [{ account: 'bank', delta_micros: 1 }], [{ kind: 'accounts', id: 'bank', revision: 2 }]);
    assert.equal((await user(A, tx => push(tx, adjust))).status, 'accepted');
    await denies(() => user(A, tx => push(tx, op2([]))), '22023');
  });
  await test('malformed effects, requirements and mixed versions fail closed', async () => {
    const bad = [
      op2([], [{ account: 'bank', delta_micros: 0 }]),
      op2([], [{ account: 'bank', delta_micros: 1.5 }]),
      op2([], [{ account: 'bank', delta_micros: 9000000000000001 }]),
      op2([], [{ account: 'bank', delta_micros: 1 }, { account: 'bank', delta_micros: 2 }]),
      op2([], [{ account: '', delta_micros: 1 }]),
      op2([edit('x', 0, {})], [], [{ kind: 'accounts', id: 'bank', revision: -1 }]),
      op2([edit('bank', 2, {}, 'accounts')], [], [{ kind: 'accounts', id: 'bank', revision: 2 }]),
      op2([edit('x', 0, {})], [], [], d1, { label: '' }),
      { ...op([edit('y', 0, {})]), dataset_id: ds2, epoch: ep2, device_id: d1, effects: [] },
      { ...op2([edit('z', 0, {})]), effects: undefined },
      { ...op2([edit('z', 0, {})]), protocol: undefined },
    ];
    for (const item of bad) await denies(() => user(A, tx => push(tx, item)), '22023');
    assert.equal(BigInt(await balance('bank')), 992200001n);
  });
  await test('pull returns v2 payloads byte for byte in revision order', async () => {
    const page = await user(A, tx => pull(tx, 0, d2, ds2, ep2));
    assert.deepEqual(page.map(r => r.revision), [1, 2, 3, 4, 5]);
    assert(page.every(r => r.hash === hash(r.payload)));
    assert.equal(JSON.parse(page[1].payload).effects[0].delta_micros, -7500000);
  });
  await test('balance projection is private to its owner', async () => {
    await db.exec('grant usage on schema nexo_sync_lab_private to authenticated; grant select on nexo_sync_lab_private.balances to authenticated;');
    assert.equal((await user(B, tx => tx.query('select * from nexo_sync_lab_private.balances'))).rows.length, 0);
    assert((await user(A, tx => tx.query('select * from nexo_sync_lab_private.balances'))).rows.length > 0);
    await db.exec('revoke all on nexo_sync_lab_private.balances from authenticated; revoke all on schema nexo_sync_lab_private from authenticated;');
    await denies(() => user(A, tx => tx.query('select * from nexo_sync_lab_private.balances')), '42501');
  });
  // ── MCP connectors ───────────────────────────────────────────────────
  const tokenHash = token => createHash('sha256').update(token).digest('hex');
  let connector;
  await test('owner creates a read connector; token shown once, only hash stored', async () => {
    connector = await user(A, tx => rpc(tx, 'nexo_mcp_create_connector', [ds2, ' Claude ']));
    assert.match(connector.token, /^nexo_mcp_[0-9a-f]{64}$/);
    assert.equal(connector.label, 'Claude');
    const listed = await user(A, tx => rpc(tx, 'nexo_mcp_list_connectors', []));
    assert.equal(listed.length, 1);
    assert.equal(JSON.stringify(listed).includes(connector.token), false);
    const stored = (await db.query('select token_hash from nexo_mcp_private.connectors')).rows[0];
    assert.equal(stored.token_hash, tokenHash(connector.token));
  });
  await test('connector cannot target another user dataset', async () => {
    await denies(() => user(B, tx => rpc(tx, 'nexo_mcp_create_connector', [ds2, 'x'])), '42501');
    await denies(() => user(null, tx => rpc(tx, 'nexo_mcp_create_connector', [ds2, 'x']), 'anon'), '42501');
  });
  await test('server functions are service-role only', async () => {
    const hash = tokenHash(connector.token);
    for (const role of ['anon', 'authenticated']) {
      await denies(() => user(A, tx => rpc(tx, 'nexo_mcp_authenticate', [hash]), role), '42501');
      await denies(() => user(A, tx => rpc(tx, 'nexo_mcp_ledger', [connector.id]), role), '42501');
    }
  });
  await test('token authenticates and ledger is scoped to its dataset', async () => {
    const found = await user(null, tx => rpc(tx, 'nexo_mcp_authenticate', [tokenHash(connector.token)]), 'service_role');
    assert.equal(found.id, connector.id);
    assert.equal(found.dataset_id, ds2);
    assert.equal(await user(null, tx => rpc(tx, 'nexo_mcp_authenticate', [tokenHash(connector.token + 'x')]), 'service_role'), null);
    const ledger = await user(null, tx => rpc(tx, 'nexo_mcp_ledger', [connector.id]), 'service_role');
    assert(ledger.entities.some(e => e.kind === 'transactions'));
    assert(ledger.entities.every(e => !['private-b'].includes(e.value?.id)));
    assert.equal(BigInt(ledger.balances.find(b => b.account_id === 'bank').micros), 992200001n);
    await user(null, tx => rpc(tx, 'nexo_mcp_audit', [connector.id, 'get_accounts', true]), 'service_role');
    assert.equal((await db.query('select count(*)::int as n from nexo_mcp_private.audit')).rows[0].n, 1);
  });
  await test('revoked connector stops authenticating; limit of five active', async () => {
    await denies(() => user(B, tx => rpc(tx, 'nexo_mcp_revoke_connector', [connector.id])), '42501');
    await user(A, tx => rpc(tx, 'nexo_mcp_revoke_connector', [connector.id]));
    assert.equal(await user(null, tx => rpc(tx, 'nexo_mcp_authenticate', [tokenHash(connector.token)]), 'service_role'), null);
    await denies(() => user(null, tx => rpc(tx, 'nexo_mcp_ledger', [connector.id]), 'service_role'), '42501');
    for (let i = 0; i < 5; i++) await user(A, tx => rpc(tx, 'nexo_mcp_create_connector', [ds2, `c${i}`]));
    await denies(() => user(A, tx => rpc(tx, 'nexo_mcp_create_connector', [ds2, 'sexto'])), '22023');
  });
  await test('MCP tables have RLS and no direct client grants', async () => {
    const rows = (await db.query(`select relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'nexo_mcp_private' and relkind = 'r'`)).rows;
    assert.equal(rows.length, 2);
    assert(rows.every(r => r.relrowsecurity));
    await denies(() => user(A, tx => tx.query('select * from nexo_mcp_private.connectors')), '42501');
  });
  console.log(`SQL LAB: ${passed} tests passed; synthetic local data only.`);
} finally {
  await db.close();
}
