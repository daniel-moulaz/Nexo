// Minimal Pluggy API client (read-only). Credentials come from Supabase
// secrets set by the account owner; they never reach the app or logs.
// No payment, Pix or transfer endpoint is called or exposed.
import type { PluggyAccount, PluggyTransaction } from "./normalize.ts";

export class PluggyError extends Error {
  readonly status: number;
  readonly retryable: boolean;
  constructor(status: number, retryable: boolean) {
    super(`pluggy_${status}`);
    this.status = status;
    this.retryable = retryable;
  }
}

type Fetch = (url: string, init?: RequestInit) => Promise<Response>;

export class PluggyClient {
  private readonly clientId: string;
  private readonly clientSecret: string;
  private readonly fetcher: Fetch;
  private readonly base: string;
  private apiKey: string | null = null;

  constructor(clientId: string, clientSecret: string, fetcher: Fetch = fetch, base = "https://api.pluggy.ai") {
    this.clientId = clientId;
    this.clientSecret = clientSecret;
    this.fetcher = fetcher;
    this.base = base;
  }

  private async auth(): Promise<string> {
    const response = await this.fetcher(`${this.base}/auth`, {
      method: "POST",
      redirect: "error",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ clientId: this.clientId, clientSecret: this.clientSecret }),
    });
    if (!response.ok) throw new PluggyError(response.status, response.status >= 500);
    const body = await response.json() as { apiKey?: unknown };
    if (typeof body.apiKey !== "string") throw new PluggyError(502, true);
    return (this.apiKey = body.apiKey);
  }

  /// GET with one transparent re-authentication when the 2h key expires.
  private async get<T>(path: string): Promise<T> {
    for (let attempt = 0; attempt < 2; attempt++) {
      const key = this.apiKey ?? await this.auth();
      const response = await this.fetcher(`${this.base}${path}`, {
        redirect: "error",
        headers: { "X-API-KEY": key, Accept: "application/json" },
      });
      if (response.status === 401 && attempt === 0) {
        this.apiKey = null;
        continue;
      }
      if (!response.ok) {
        throw new PluggyError(response.status, response.status === 429 || response.status >= 500);
      }
      return await response.json() as T;
    }
    throw new PluggyError(401, false);
  }

  item(id: string) {
    return this.get<Record<string, unknown>>(`/items/${encodeURIComponent(id)}`);
  }

  async accounts(itemId: string): Promise<PluggyAccount[]> {
    const page = await this.get<{ results: PluggyAccount[] }>(`/accounts?itemId=${encodeURIComponent(itemId)}`);
    return page.results ?? [];
  }

  /// Cursor pagination of GET /v2/transactions; `next` is appended as-is.
  async transactions(accountId: string, dateFrom: string, maxPages = 50): Promise<PluggyTransaction[]> {
    const all: PluggyTransaction[] = [];
    let query: string | null =
      `?accountId=${encodeURIComponent(accountId)}&dateFrom=${encodeURIComponent(dateFrom)}`;
    for (let page = 0; query && page < maxPages; page++) {
      if (!query.startsWith("?")) throw new PluggyError(502, false);
      const body = await this.get<{ results: PluggyTransaction[]; next: string | null }>(`/v2/transactions${query}`);
      all.push(...(body.results ?? []));
      query = body.next;
    }
    if (query) throw new PluggyError(507, true); // more pages than allowed in one run
    return all;
  }
}
