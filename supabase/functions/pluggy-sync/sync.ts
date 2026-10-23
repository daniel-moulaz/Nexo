// One refresh of a person's Pluggy connections: read accounts and recent
// transactions, turn them into suggestions and store them with the tested
// merge rules. Read-only towards Pluggy; never creates money in the ledger.
import {
  type AccountSnapshot, type BillSnapshot, type ItemHealth, latestMovementAt, isSkip, itemHealth, merge, type PluggyAccount,
  type PluggyBill, type PluggyTransaction, type Suggestion, toAccountSnapshot, toBillSnapshot, toSuggestion,
} from "./normalize.ts";
import { PluggyError } from "./pluggy.ts";

export interface Source {
  item(id: string): Promise<Record<string, unknown>>;
  accounts(itemId: string): Promise<PluggyAccount[]>;
  transactions(accountId: string, dateFrom: string): Promise<PluggyTransaction[]>;
  /// Official invoices of a card (optional).
  bills?(accountId: string): Promise<PluggyBill[]>;
}

export interface StoredItem { item_id: string; label: string; last_fetch_at: string | null }
export type Stored = Suggestion & { review: "pending" | "confirmed" | "ignored" };
export type Row = Suggestion & { action: "insert" | "update" | "flag_changed" };

export interface Store {
  items(owner: string): Promise<StoredItem[]>;
  stored(owner: string, ids: string[]): Promise<Stored[]>;
  store(owner: string, itemId: string, health: ItemHealth, rows: Row[]): Promise<number>;
  /// Latest balances and card limits of the item (optional: older servers).
  accounts?(owner: string, itemId: string, updatedAt: string | null, rows: AccountSnapshot[]): Promise<void>;
  /// Official invoices of one card; the bank's list replaces the kept one.
  bills?(owner: string, accountId: string, rows: BillSnapshot[]): Promise<void>;
}

export interface ItemResult {
  item_id: string;
  label: string;
  health: ItemHealth | null;
  fetched: boolean;
  written: number;
  skipped: number;
  /// Official invoices read per card, or the error code. Never amounts.
  bills?: (number | string)[];
}

/// Meu Pluggy refreshes once a day; reading more often only costs requests.
export const minIntervalMs = 60 * 60 * 1000;
/// Suggestions older than this are not useful to review any more.
export const windowDays = 35;

export async function syncOwner(owner: string, source: Source, store: Store,
  options: { now?: Date; force?: boolean } = {}): Promise<ItemResult[]> {
  const now = options.now ?? new Date();
  const dateFrom = new Date(now.getTime() - windowDays * 86400000).toISOString().slice(0, 10);
  const results: ItemResult[] = [];
  for (const item of await store.items(owner)) {
    const last = item.last_fetch_at ? Date.parse(item.last_fetch_at) : NaN;
    // Even a forced refresh waits a few minutes between reads of one item.
    const wait = options.force ? 5 * 60 * 1000 : minIntervalMs;
    if (!isNaN(last) && now.getTime() - last < wait) {
      results.push({ item_id: item.item_id, label: item.label, health: null, fetched: false, written: 0, skipped: 0 });
      continue;
    }
    let health: ItemHealth;
    const incoming: Suggestion[] = [];
    const snapshots: AccountSnapshot[] = [];
    let updatedAt: string | null = null;
    let skipped = 0;
    const bills: (number | string)[] = [];
    const cardBills = new Map<string, BillSnapshot[]>();
    try {
      const raw = await source.item(item.item_id);
      health = itemHealth(raw as Parameters<typeof itemHealth>[0], now);
      for (const account of await source.accounts(item.item_id)) {
        const snapshot = toAccountSnapshot(account);
        if (snapshot) snapshots.push(snapshot);
        if (account.type === "CREDIT" && source.bills) {
          try {
            const rows = (await source.bills(account.id)).map(toBillSnapshot)
              .filter((b): b is BillSnapshot => b !== null)
              .sort((a, b) => b.due_date.localeCompare(a.due_date)).slice(0, 24);
            cardBills.set(account.id, rows);
            bills.push(rows.length);
          } catch (error) {
            if (!(error instanceof PluggyError)) throw error;
            bills.push(error.message);
          }
        }
        const txs = await source.transactions(account.id, dateFrom);
        const latest = latestMovementAt(txs);
        if (latest && (!updatedAt || latest > updatedAt)) updatedAt = latest;
        for (const tx of txs) {
          const s = toSuggestion(tx, account);
          if (isSkip(s)) skipped++;
          else incoming.push(s);
        }
      }
    } catch (error) {
      if (!(error instanceof PluggyError)) throw error;
      health = {
        state: error.status === 404 ? "reconnect" : "error",
        message: error.status === 404
          ? "Conexão não encontrada no Pluggy. Confira o identificador ou reconecte pelo Meu Pluggy."
          : `Não foi possível ler este banco agora (${error.message}). Os dados já recebidos continuam.`,
      };
      await store.store(owner, item.item_id, health, []);
      results.push({ item_id: item.item_id, label: item.label, health, fetched: false, written: 0, skipped: 0 });
      continue;
    }
    const known = new Map<string, Stored>();
    for (let i = 0; i < incoming.length; i += 500) {
      for (const s of await store.stored(owner, incoming.slice(i, i + 500).map((r) => r.external_id))) {
        known.set(s.external_id, s);
      }
    }
    const rows: Row[] = [];
    for (const s of incoming) {
      const { action, row } = merge(known.get(s.external_id), s);
      if (action !== "keep") rows.push({ ...row, action });
    }
    let written = 0;
    for (let i = 0; i < Math.max(rows.length, 1); i += 500) {
      written += await store.store(owner, item.item_id, health, rows.slice(i, i + 500));
    }
    if (store.accounts) await store.accounts(owner, item.item_id, updatedAt, snapshots);
    // After the accounts: each bill belongs to a stored card.
    if (store.bills) for (const [accountId, rows] of cardBills) await store.bills(owner, accountId, rows);
    results.push({
      item_id: item.item_id, label: item.label, health, fetched: true, written, skipped,
      bills: bills.length ? bills : undefined,
    });
  }
  return results;
}
