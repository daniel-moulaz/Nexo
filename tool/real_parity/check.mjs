// Compares the server mirror with the app on the real ledger copy made by
// test/real_parity/real_parity_test.dart (see its header). Prints only
// pass/fail and field names, never amounts.
import { readFile } from 'node:fs/promises';
import { analyze } from '../../supabase/functions/nexo-mcp/finance.ts';
import { spendingTypes } from '../../supabase/functions/nexo-mcp/envelopes.ts';
import { cardInvoices } from '../../supabase/functions/nexo-mcp/invoices.ts';
import { callAction } from '../../supabase/functions/nexo-mcp/actions.ts';
import { envelopes as defs } from '../../supabase/functions/nexo-mcp/envelopes.ts';

const { today, ledger } = JSON.parse(await readFile(new URL('../../build/real_parity/mirror.json', import.meta.url), 'utf8'));
const expected = JSON.parse(await readFile(new URL('../../build/real_parity/expected.json', import.meta.url), 'utf8'));
let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) pass++; else { fail++; console.log(`FAIL ${name}`); } };
const near = (a, b) => Math.abs(a - b) <= 1; // one cent of rounding

for (const m of expected.months) {
  const a = analyze(ledger, { from: m.from, to: m.to });
  for (const k of ['income', 'expense', 'refunds', 'pendingExpense', 'transfers', 'result']) {
    check(`month ${m.from.slice(0, 7)} ${k}`, a[k] === m[k]);
  }
  const keys = new Set([...Object.keys(a.categories), ...Object.keys(m.categories)]);
  check(`month ${m.from.slice(0, 7)} categories`, [...keys].every((k) => (a.categories[k] ?? 0) === (m.categories[k] ?? 0)));
}

const deps = { enqueue: async () => ({ id: 'x', status: 'pending' }), request: async () => null,
  suggestions: async () => [], ignoreSuggestions: async () => 0 };
const budgets = (await callAction('get_budgets', {}, ledger, today, deps)).budgets;
for (const b of expected.budgets) {
  const s = budgets.find((x) => x.id === b.id);
  check(`budget ${expected.budgets.indexOf(b) + 1} limit`, !!s && near(Math.round(s.limit * 100), b.limit));
  check(`budget ${expected.budgets.indexOf(b) + 1} spent`, !!s && near(Math.round(s.spent * 100), b.spent));
}

const shares = Object.fromEntries(defs.map((e) => [e.id, e.defaultShare]));
const env = spendingTypes(ledger, expected.envelopes.month, shares, 1800);
for (const line of env.types) {
  const e = expected.envelopes.lines[line.type];
  check(`spending type ${line.type} planned`, near(Math.round(line.planned * 100), e.planned));
  check(`spending type ${line.type} spent`, near(Math.round(line.spent * 100), e.spent));
}
check('spending without type', near(Math.round(env.without_type.spent * 100), expected.envelopes.unassignedSpent));

const cards = cardInvoices(ledger, today).cards;
for (const inv of expected.invoices) {
  const card = cards.find((c) => c.card_id === inv.card);
  const got = card?.invoices.find((i) => i.closing_date === inv.closing);
  if (!got && inv.total === 0 && inv.paid === 0) { pass++; continue; } // an empty old cycle is not listed
  check(`invoice ${inv.closing} total`, !!got && near(Math.round(got.total * 100), inv.total));
  check(`invoice ${inv.closing} paid`, !!got && near(Math.round(got.paid * 100), inv.paid));
}
console.log(`REAL COPY: ${pass} passed, ${fail} failed (amounts not shown).`);
