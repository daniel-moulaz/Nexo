// Wakes the person's phone right after the assistant queues a request, so
// it is recorded with the app closed. Firebase Cloud Messaging HTTP v1 with
// a service account kept as the FCM_SERVICE_ACCOUNT secret; without it
// nothing is sent and the phone checks every 15 minutes on its own.
//
// The message carries no data about the request (only kind=queue): the
// phone reads the queue with its own session.

export interface ServiceAccount {
  client_email: string;
  private_key: string;
  project_id: string;
}

type Fetch = (url: string, init: RequestInit) => Promise<Response>;

export function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw) return null;
  try {
    const a = JSON.parse(raw) as Partial<ServiceAccount>;
    if (typeof a.client_email !== "string" || typeof a.private_key !== "string" || typeof a.project_id !== "string") {
      return null;
    }
    if (!/^[a-z0-9-]{4,40}$/.test(a.project_id)) return null;
    return a as ServiceAccount;
  } catch {
    return null;
  }
}

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64urlText = (text: string) => b64url(new TextEncoder().encode(text));

function pemToDer(pem: string): Uint8Array {
  const body = pem.replace(/-----[A-Z ]+-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/// A signed JWT for Google's token endpoint (RS256).
export async function assertion(account: ServiceAccount, nowSeconds: number): Promise<string> {
  const header = b64urlText(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64urlText(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  }));
  const key = await crypto.subtle.importKey("pkcs8", pemToDer(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key,
    new TextEncoder().encode(`${header}.${claims}`)));
  return `${header}.${claims}.${b64url(signature)}`;
}

let cached: { token: string; until: number; email: string } | null = null;
export function clearTokenCache() {
  cached = null;
}

async function accessToken(account: ServiceAccount, fetcher: Fetch, nowMs: number): Promise<string> {
  if (cached && cached.email === account.client_email && cached.until > nowMs) return cached.token;
  const response = await fetcher("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: await assertion(account, Math.floor(nowMs / 1000)),
    }).toString(),
  });
  if (!response.ok) throw new Error(`push_auth_${response.status}`);
  const data = await response.json() as { access_token?: string; expires_in?: number };
  if (!data.access_token) throw new Error("push_auth_empty");
  cached = { token: data.access_token, email: account.client_email, until: nowMs + Math.max(60, (data.expires_in ?? 3600) - 300) * 1000 };
  return cached.token;
}

export interface WakeResult {
  sent: number;
  /// Tokens FCM says no longer exist (app uninstalled, data cleared).
  gone: string[];
  failed: number;
}

/// Sends the silent wake-up to every token; never throws.
export async function wake(targets: { token: string }[], account: ServiceAccount | null,
  fetcher: Fetch = fetch, nowMs = Date.now()): Promise<WakeResult> {
  const result: WakeResult = { sent: 0, gone: [], failed: 0 };
  if (!account || targets.length === 0) return result;
  let token: string;
  try {
    token = await accessToken(account, fetcher, nowMs);
  } catch {
    result.failed = targets.length;
    return result;
  }
  for (const target of targets.slice(0, 5)) {
    try {
      const response = await fetcher(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: target.token,
            data: { kind: "queue" },
            // High priority lets Android run the app for a few seconds even
            // in Doze; a request older than 10 minutes is handled anyway by
            // the 15-minute check.
            android: { priority: "HIGH", ttl: "600s" },
          },
        }),
      });
      if (response.ok) {
        result.sent++;
      } else if (response.status === 404 || response.status === 400) {
        const text = await response.text();
        if (/UNREGISTERED|INVALID_ARGUMENT|not a valid FCM registration token/i.test(text)) result.gone.push(target.token);
        else result.failed++;
      } else {
        result.failed++;
      }
    } catch {
      result.failed++;
    }
  }
  return result;
}
