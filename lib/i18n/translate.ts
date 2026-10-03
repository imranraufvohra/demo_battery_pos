import en, { type TKey } from "./en";
import ar from "./ar";
import type { Lang } from "./config";

const DICTS: Record<Lang, Record<TKey, string>> = { en, ar };

export type TFunction = (key: TKey, params?: Record<string, string | number>) => string;

/** Pure translator (no React, no cookies). Falls back to English, then to the key itself. */
export function makeT(lang: Lang): TFunction {
  const dict = DICTS[lang] ?? en;
  return (key, params) => {
    let s: string = dict[key] ?? en[key] ?? key;
    if (params) for (const [k, v] of Object.entries(params)) s = s.replaceAll(`{${k}}`, String(v));
    return s;
  };
}
