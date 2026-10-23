// Pluggy → Nexo suggestion mapping. Pure functions, tested in Node with
// fixtures shaped by the official OpenAPI spec (api.pluggy.ai/oas3.json).
// A Pluggy transaction never becomes money by itself: it becomes a
// suggestion the person reviews, keyed by the Pluggy id so refreshes,
// reconnections and webhooks update instead of duplicating.

export interface PluggyAccount {
  id: string;
  type: "BANK" | "CREDIT";
  subtype: string;
  name: string;
  currencyCode: string;
  itemId: string;
  marketingName?: string | null;
  /// BANK: available to spend. CREDIT: open balance of the unpaid invoice.
  balance?: number | null;
  creditData?: {
    creditLimit?: number | null;
    availableCreditLimit?: number | null;
    minimumPayment?: number | null;
    balanceCloseDate?: string | null;
    balanceDueDate?: string | null;
  } | null;
}

/// What the app needs to compare balances and show the card limit. Account
/// number, owner and tax number are deliberately left out.
export interface AccountSnapshot {
  account_id: string;
  type: "BANK" | "CREDIT";
  subtype: string;
  name: string;
  currency: string;
  balance_cents: number | null;
  credit_limit_cents: number | null;
  available_cents: number | null;
  minimum_payment_cents: number | null;
  close_date: string | null;
  due_date: string | null;
}

const cents = (v: unknown): number | null =>
  typeof v === "number" && isFinite(v) && Math.abs(v) < 1e11 ? Math.round(v * 100) : null;
const isoDay = (v: unknown): string | null =>
  typeof v === "string" && /^\d{4}-\d{2}-\d{2}/.test(v) ? v.slice(0, 10) : null;

export function toAccountSnapshot(a: PluggyAccount): AccountSnapshot | null {
  if (!a.id || (a.type !== "BANK" && a.type !== "CREDIT")) return null;
  const credit = a.type === "CREDIT" ? a.creditData ?? null : null;
  return {
    account_id: a.id,
    type: a.type,
    subtype: String(a.subtype ?? "").slice(0, 40),
    name: (a.marketingName || a.name || "Conta").trim().slice(0, 60),
    currency: String(a.currencyCode ?? "BRL").slice(0, 3),
    balance_cents: cents(a.balance),
    credit_limit_cents: cents(credit?.creditLimit),
    available_cents: cents(credit?.availableCreditLimit),
    minimum_payment_cents: cents(credit?.minimumPayment),
    close_date: isoDay(credit?.balanceCloseDate),
    due_date: isoDay(credit?.balanceDueDate),
  };
}

/// When the bank data behind this item was last refreshed by Pluggy.
export function bankUpdatedAt(item: Record<string, unknown>): string | null {
  const v = item.lastUpdatedAt;
  return typeof v === "string" && !isNaN(Date.parse(v)) ? new Date(v).toISOString() : null;
}

export interface PluggyTransaction {
  id: string;
  description: string;
  descriptionRaw?: string | null;
  currencyCode: string;
  amount: number;
  amountInAccountCurrency?: number;
  date: string;
  type: "DEBIT" | "CREDIT";
  status?: "POSTED" | "PENDING";
  category?: string;
  accountId: string;
  creditCardMetadata?: { installmentNumber?: number; totalInstallments?: number } | null;
  operationType?: string | null;
  updatedAt: string;
}

export interface Suggestion {
  external_id: string; // pluggy:<transaction id>
  account_external_id: string;
  item_id: string;
  amount_cents: number;
  kind: "income" | "expense" | "refund" | "transfer";
  medium: "bank" | "credit";
  description: string;
  occurred_at: number; // epoch ms
  settled: boolean;
  installment: string | null;
  source_updated_at: string;
}

export type Skip = { external_id: string; reason: "unsupported_currency" | "invalid" | "zero" };

const CARD_PAYMENT = /pagamento\s+(de\s+|da\s+)?fatura|payment|bill payment/i;
// Only strong evidence of moving money between the person's own accounts.
// A Pix or TED alone is often a purchase or a salary: defaulting it to a
// transfer would hide spending or income, so it stays expense/income.
const OWN_TRANSFER =
  /entre contas|mesma titularidade|transfer[eê]ncia (para|da|de) (sua |minha )?(conta|poupan[cç]a)|aplica[cç][aã]o|resgate/i;

/// Direction comes from `type` (Pluggy normalizes credit cards so that
/// purchases are always DEBIT). Amount sign is not trusted.
export function toSuggestion(
  tx: PluggyTransaction,
  account: PluggyAccount,
  mainCurrency = "BRL",
): Suggestion | Skip {
  const external_id = `pluggy:${tx.id}`;
  if (!tx.id || !tx.accountId || tx.accountId !== account.id || isNaN(Date.parse(tx.date)) ||
      (tx.type !== "DEBIT" && tx.type !== "CREDIT") || typeof tx.amount !== "number" || !isFinite(tx.amount)) {
    return { external_id, reason: "invalid" };
  }
  // Foreign purchases: use the account-currency amount when Pluggy gives it.
  let amount: number | undefined;
  if (account.currencyCode !== mainCurrency) return { external_id, reason: "unsupported_currency" };
  if (tx.currencyCode === mainCurrency) amount = tx.amount;
  else if (typeof tx.amountInAccountCurrency === "number") amount = tx.amountInAccountCurrency;
  if (amount === undefined || !isFinite(amount)) return { external_id, reason: "unsupported_currency" };
  const cents = Math.round(Math.abs(amount) * 100);
  if (cents === 0) return { external_id, reason: "zero" };
  const credit = account.type === "CREDIT";
  const text = `${tx.description} ${tx.category ?? ""} ${tx.operationType ?? ""}`;
  let kind: Suggestion["kind"];
  if (tx.type === "DEBIT") kind = OWN_TRANSFER.test(text) && !credit ? "transfer" : "expense";
  else if (credit) kind = CARD_PAYMENT.test(text) ? "transfer" : "refund";
  else kind = OWN_TRANSFER.test(text) ? "transfer" : "income";
  const meta = tx.creditCardMetadata;
  return {
    external_id,
    account_external_id: account.id,
    item_id: account.itemId,
    amount_cents: cents,
    kind,
    medium: credit ? "credit" : "bank",
    description: (tx.description || tx.descriptionRaw || "Movimentação bancária").trim().slice(0, 80),
    occurred_at: Date.parse(tx.date),
    settled: tx.status !== "PENDING",
    installment: meta?.installmentNumber && meta?.totalInstallments
      ? `${meta.installmentNumber}/${meta.totalInstallments}` : null,
    source_updated_at: tx.updatedAt,
  };
}

export const isSkip = (v: Suggestion | Skip): v is Skip => "reason" in v;

/// What a refresh should do with a stored suggestion. The person's decision
/// (confirmed or ignored) is never undone by the bank changing its data.
export function merge(
  stored: (Suggestion & { review: "pending" | "confirmed" | "ignored" }) | undefined,
  incoming: Suggestion,
): { action: "insert" | "update" | "keep" | "flag_changed"; row: Suggestion } {
  if (!stored) return { action: "insert", row: incoming };
  if (incoming.source_updated_at <= stored.source_updated_at) return { action: "keep", row: stored };
  const material = stored.amount_cents !== incoming.amount_cents || stored.kind !== incoming.kind ||
    stored.occurred_at !== incoming.occurred_at;
  if (stored.review === "pending") return { action: "update", row: incoming };
  // Already decided: never rewrite money; only tell the person if it matters.
  return { action: material ? "flag_changed" : "keep", row: material ? incoming : stored };
}

export interface ItemHealth {
  state: "ok" | "updating" | "reconnect" | "expiring" | "error";
  message: string;
}

export function itemHealth(item: {
  status: string;
  executionStatus?: string;
  error?: { code?: string } | null;
  consentExpiresAt?: string | null;
}, now: Date): ItemHealth {
  const code = item.error?.code ?? "";
  if (item.status === "LOGIN_ERROR" || code === "USER_AUTHORIZATION_EXPIRED" ||
      item.executionStatus === "USER_AUTHORIZATION_EXPIRED") {
    return { state: "reconnect", message: "A autorização do banco venceu ou foi recusada. Reconecte pelo Meu Pluggy." };
  }
  if (item.status === "UPDATING") return { state: "updating", message: "O banco está sendo atualizado." };
  if (item.status === "OUTDATED" || item.status === "WAITING_USER_INPUT" || item.status === "WAITING_USER_ACTION") {
    return { state: "error", message: "A última atualização não terminou. Os dados podem estar desatualizados." };
  }
  if (item.consentExpiresAt) {
    const days = (Date.parse(item.consentExpiresAt) - now.getTime()) / 86400000;
    if (days <= 0) return { state: "reconnect", message: "A autorização do banco venceu. Reconecte pelo Meu Pluggy." };
    if (days <= 15) return { state: "expiring", message: `A autorização do banco vence em ${Math.ceil(days)} dia(s).` };
  }
  return { state: "ok", message: "Conectado." };
}
