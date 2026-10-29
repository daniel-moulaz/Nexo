// App settings the assistant may read and change, mirroring
// lib/sync/assistant_settings.dart (a test compares both lists). Shared
// settings live in the synced ledger (same on every device); the others
// belong to each device, which reports them to the server.
import { type Ledger, type Row, text } from "./finance.ts";
import { envelopes } from "./envelopes.ts";

export interface SettingDef {
  key: string;
  label: string;
  kind: "bool" | "number" | "time" | "enum" | "string" | "currency" | "shares" | "goal_ids" | "cards";
  shared?: boolean;
  values?: string[];
  default: unknown;
}

const seeds = ["violet", "blue", "green", "rose", "amber", "teal", "orange", "indigo", "cyan", "pink", "lime",
  "deep_purple", "crimson", "midnight", "forest", "mint", "olive", "sage", "sky", "navy", "cobalt", "ocean", "coral",
  "gold", "slate", "magenta", "turquoise", "brown", "lavender"];
const fonts = ["default", "plus_jakarta_sans", "dm_sans", "inter", "nunito_sans", "space_grotesk", "outfit", "sora",
  "poppins", "nunito"];
export const homeCards = ["daily", "month", "week", "categories", "netWorth", "future", "budget", "cards"];

export const settingDefs: SettingDef[] = [
  { key: "referenceIncome", label: "Renda de referência dos tipos de gasto (0: renda fixa do ciclo)", kind: "number", shared: true, default: 0 },
  { key: "envelopeShares", label: "% da renda de referência por tipo de gasto; soma 100", kind: "shares", shared: true,
    default: Object.fromEntries(envelopes.map((e) => [e.id, e.defaultShare])) },
  { key: "weekStart", label: "Primeiro dia da semana dos orçamentos semanais", kind: "enum", shared: true, values: ["monday", "sunday"], default: "monday" },
  { key: "lockedGoalIds", label: "Objetivos cujo dinheiro fica fora do saldo livre do Hoje", kind: "goal_ids", shared: true, default: [] },
  { key: "budgetAlertsEnabled", label: "Aviso quando um orçamento estoura", kind: "bool", default: true },
  { key: "dailyReminderEnabled", label: "Lembrete diário para lançar gastos", kind: "bool", default: false },
  { key: "dailyReminderTime", label: "Hora do lembrete diário (HH:mm)", kind: "time", default: "22:00" },
  { key: "hideBalance", label: "Esconder valores na tela", kind: "bool", default: false },
  { key: "themeMode", label: "Tema claro, escuro ou do sistema", kind: "enum", values: ["system", "light", "dark"], default: "dark" },
  { key: "themeSeed", label: "Cor do tema", kind: "enum", values: seeds, default: "violet" },
  { key: "appFont", label: "Fonte do app", kind: "enum", values: fonts, default: "default" },
  { key: "amoledSurfaces", label: "Fundo preto puro no tema escuro", kind: "bool", default: false },
  { key: "dynamicColorEnabled", label: "Cores do papel de parede (Android)", kind: "bool", default: false },
  { key: "hapticsEnabled", label: "Vibração ao tocar", kind: "bool", default: true },
  { key: "homeCards", label: "Cartões visíveis do Hoje, em ordem", kind: "cards", values: homeCards, default: [] },
  { key: "userName", label: "Nome mostrado no app", kind: "string", default: "" },
  { key: "currency", label: "Moeda principal (ISO, ex.: BRL)", kind: "currency", default: "BRL" },
];

export const settingDef = (key: string) => settingDefs.find((d) => d.key === key);

/// The shared settings as the app uses them: stored value or default.
export function sharedSettings(l: Ledger): Record<string, unknown> {
  const stored = new Map((l.sharedSettings ?? []).map((r: Row) => [text(r.key), text(r.value)]));
  const out: Record<string, unknown> = {};
  for (const d of settingDefs.filter((x) => x.shared)) {
    const raw = stored.get(d.key);
    let value = d.default;
    if (raw !== undefined) {
      try {
        value = JSON.parse(raw);
      } catch {
        // A malformed row: the app keeps its default too.
      }
    }
    out[d.key] = value;
  }
  return out;
}

/// Checks a value like the app does; returns it normalized or an error text.
export function checkSetting(key: string, value: unknown, goalIds: Set<string>): { ok: unknown } | { error: string } {
  const d = settingDef(key);
  if (!d) return { error: `Configuração desconhecida: ${key}. Use get_settings para ver as disponíveis.` };
  const bad = (why: string) => ({ error: `${key}: ${why}` });
  switch (d.kind) {
    case "bool":
      return typeof value === "boolean" ? { ok: value } : bad("use verdadeiro ou falso.");
    case "number":
      return typeof value === "number" && isFinite(value) && value >= 0 && value <= 1e9
        ? { ok: Math.round(value * 100) / 100 } : bad("use um valor de 0 a 1 bilhão.");
    case "time":
      return typeof value === "string" && /^([01]\d|2[0-3]):[0-5]\d$/.test(value) ? { ok: value } : bad("use HH:mm.");
    case "enum":
      return typeof value === "string" && d.values!.includes(value) ? { ok: value } : bad(`use ${d.values!.join(", ")}.`);
    case "string":
      return typeof value === "string" && value.trim().length <= 60 ? { ok: value.trim() } : bad("até 60 letras.");
    case "currency":
      return typeof value === "string" && /^[A-Z]{3}$/.test(value) ? { ok: value } : bad("use o código de 3 letras, como BRL.");
    case "shares": {
      if (!value || typeof value !== "object" || Array.isArray(value)) return bad("informe a % de cada tipo.");
      const v = value as Record<string, unknown>;
      const unknown = Object.keys(v).filter((k) => !envelopes.some((e) => e.id === k));
      if (unknown.length) return bad(`tipos válidos: ${envelopes.map((e) => e.id).join(", ")}.`);
      const out: Record<string, number> = {};
      for (const e of envelopes) {
        const n = v[e.id];
        if (typeof n !== "number" || !Number.isInteger(n) || n < 0 || n > 100) return bad(`${e.id} deve ser um inteiro de 0 a 100.`);
        out[e.id] = n;
      }
      const total = Object.values(out).reduce((s, n) => s + n, 0);
      return total === 100 ? { ok: out } : bad(`as porcentagens somam ${total}%, devem somar 100%.`);
    }
    case "goal_ids": {
      if (!Array.isArray(value) || value.some((x) => typeof x !== "string")) return bad("informe a lista de ids dos objetivos.");
      const missing = (value as string[]).find((x) => !goalIds.has(x));
      return missing ? bad(`objetivo não encontrado: ${missing}.`) : { ok: value };
    }
    case "cards":
      return Array.isArray(value) && value.length > 0 && value.every((x) => d.values!.includes(x as string))
        ? { ok: value } : bad(`use uma lista não vazia com ${d.values!.join(", ")}.`);
  }
}
