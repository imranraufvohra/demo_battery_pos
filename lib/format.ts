const NB = "\u00a0";

/** Currency / locale come from env for now (demo default USD). Phase 2: load from business_profile. */
const CURRENCY = process.env.NEXT_PUBLIC_CURRENCY ?? "USD";
const LOCALE = process.env.NEXT_PUBLIC_LOCALE ?? "en-US";
const TIMEZONE = process.env.NEXT_PUBLIC_TIMEZONE ?? "UTC";

export function formatMoney(value: number): string {
  return new Intl.NumberFormat(LOCALE, {
    style: "currency",
    currency: CURRENCY,
    maximumFractionDigits: 2,
  }).format(value);
}

/** Compact form for dashboards: 84.5K, 1.2M. */
export function formatMoneyCompact(value: number): string {
  if (Math.abs(value) < 10000) return formatMoney(value);
  return new Intl.NumberFormat(LOCALE, {
    style: "currency",
    currency: CURRENCY,
    notation: "compact",
    maximumFractionDigits: 1,
  }).format(value);
}

/** @deprecated kept so old imports keep compiling. Use formatMoney. */
export const formatRs = formatMoney;
/** @deprecated use formatMoneyCompact. */
export const formatRsCompact = formatMoneyCompact;

export function currencyLabel(): string {
  return CURRENCY + NB.replace(NB, "");
}

/** 19 Sep 2026, in the configured timezone so server and browser agree. */
export function formatDate(iso: string): string {
  return new Intl.DateTimeFormat(LOCALE, {
    day: "numeric",
    month: "short",
    year: "numeric",
    timeZone: TIMEZONE,
  }).format(new Date(iso));
}
