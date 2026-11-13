// Rules of the assistant's queue that the Edge Function applies before a
// request reaches the devices.

/// First build that records dollar fields (1.16.0+58). An older app would
/// apply the request as if it were in reais, so it must not take it.
export const DOLLAR_BUILD = 58;

/// The minimum app build a request needs, or null when any version can.
export function minBuildFor(kind: string, args: Record<string, unknown>): number | null {
  const currency = typeof args.currency === "string" ? args.currency : undefined;
  const foreign = (currency !== undefined && currency !== "BRL") ||
    args.brl_cents != null || args.fx_micros != null || args.received_cents != null ||
    (typeof args.tax_cents === "number" && args.tax_cents > 0);
  if (foreign && (kind.startsWith("investment.") || kind === "transfer.add")) return DOLLAR_BUILD;
  return null;
}

const day = (iso: string) => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null :
    `${String(d.getUTCDate()).padStart(2, "0")}/${String(d.getUTCMonth() + 1).padStart(2, "0")}/${d.getUTCFullYear()}`;
};

/// What a client (and the person reading it) learns from a refused token.
export function unauthorizedMessage(state: { state: string; revoked_at?: string } | null): string {
  const where = "Gere outro no app: Mais › Sincronizar dispositivos › Claude (IA) › Conectar ao Claude, " +
    "e troque o endereço do conector (o histórico de pedidos fica).";
  if (state?.state === "revoked") {
    const when = state.revoked_at ? day(state.revoked_at) : null;
    return `Este endereço do Nexo foi desconectado no app${when ? ` em ${when}` : ""}. ${where}`;
  }
  return `Endereço do Nexo inválido ou incompleto (confira se foi colado inteiro, até o fim). ${where}`;
}
