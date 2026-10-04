import en, { type TKey } from "./en";
import ar from "./ar";
import arText from "./ar-text";
import type { Lang } from "./config";

// Two kinds of keys live side by side:
//   1. dotted keys ("nav.home"), typed, defined in en.ts + ar.ts (shell, navigation, login)
//   2. the English sentence itself ("Running low"), translated in ar-text.ts
// Anything missing in Arabic falls back to the English text, so nothing ever shows as blank.
const DICTS: Record<Lang, Record<string, string>> = { en, ar: { ...arText, ...ar } };

// Keys that contain {placeholders} also work on finished runtime strings: the key
// "Could not delete. {0}" translates the already-built text "Could not delete. network error".
type Pattern = { re: RegExp; names: string[]; value: string; weight: number };
const PATTERNS = new Map<Lang, Pattern[]>();
function patternsFor(lang: Lang): Pattern[] {
  let list = PATTERNS.get(lang);
  if (list) return list;
  list = [];
  for (const [key, value] of Object.entries(DICTS[lang])) {
    if (!key.includes("{")) continue;
    const names: string[] = [];
    const src = key
      .split(/(\{[A-Za-z0-9_]+\})/)
      .map((part) => {
        const m = part.match(/^\{([A-Za-z0-9_]+)\}$/);
        if (m) {
          names.push(m[1]);
          return "([\\s\\S]+?)";
        }
        return part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      })
      .join("");
    list.push({ re: new RegExp("^" + src + "$"), names, value, weight: key.replace(/\{[A-Za-z0-9_]+\}/g, "").length });
  }
  // most specific pattern (most fixed text) first, so "Delete {a} {b}?" beats "Delete {a} {b}"
  list.sort((a, b) => b.weight - a.weight);
  PATTERNS.set(lang, list);
  return list;
}

// Dates and times are built by Intl in English ("21 Sep 2026", "3:45 pm", "Saturday 3 October").
// For Arabic we swap the month, weekday and am/pm words. Digits stay Western (0-9).
const AR_MONTHS: Record<string, string> = {
  jan: "يناير", feb: "فبراير", mar: "مارس", apr: "أبريل", may: "مايو", jun: "يونيو",
  jul: "يوليو", aug: "أغسطس", sep: "سبتمبر", sept: "سبتمبر", oct: "أكتوبر", nov: "نوفمبر", dec: "ديسمبر",
  january: "يناير", february: "فبراير", march: "مارس", april: "أبريل", june: "يونيو", july: "يوليو",
  august: "أغسطس", september: "سبتمبر", october: "أكتوبر", november: "نوفمبر", december: "ديسمبر",
};
const AR_DAYS: Record<string, string> = {
  monday: "الاثنين", tuesday: "الثلاثاء", wednesday: "الأربعاء", thursday: "الخميس",
  friday: "الجمعة", saturday: "السبت", sunday: "الأحد",
  mon: "الاثنين", tue: "الثلاثاء", wed: "الأربعاء", thu: "الخميس", fri: "الجمعة", sat: "السبت", sun: "الأحد",
};
const MONTH_WORD = "Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|June?|July?|Aug(?:ust)?|Sept?(?:ember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?";
const RE_MONTH = new RegExp(`(\\b\\d{1,2}\\s+)(${MONTH_WORD})\\b|\\b(${MONTH_WORD})(?=\\s+\\d{4}\\b)`, "g");
const RE_DAY_FULL = /\b(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)\b/g;
const RE_DAY_SHORT = /\b(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\b(?=[ ,]+\d)/g;
const RE_AMPM = /(\d)\s?([ap])\.?m\b\.?/gi;
export function localizeDateTokens(text: string): string {
  if (text.length > 60 || !/[A-Za-z]/.test(text)) return text;
  return text
    .replace(RE_MONTH, (m, pre, mo1, mo2) => (pre ?? "") + AR_MONTHS[(mo1 ?? mo2).toLowerCase()])
    .replace(RE_DAY_FULL, (m) => AR_DAYS[m.toLowerCase()])
    .replace(RE_DAY_SHORT, (m) => AR_DAYS[m.toLowerCase()])
    .replace(RE_AMPM, (_m, d, ap) => `${d} ${ap.toLowerCase() === "a" ? "ص" : "م"}`);
}

type Params = Record<string, unknown>;
export type TFunction = {
  (key: TKey | (string & {}), params?: Params): string;
  (key: string | null | undefined, params?: Params): string | undefined;
};

/** Pure translator (no React, no cookies). Falls back to English, then to the key itself. */
export function makeT(lang: Lang): TFunction {
  const dict = DICTS[lang] ?? en;
  const memo = new Map<string, string | null>(); // runtime strings already matched (or not) against patterns
  const t = ((key: string | null | undefined, params?: Params): string | undefined => {
    if (key == null) return undefined;
    let s: string = dict[key] ?? (en as Record<string, string>)[key] ?? key;
    if (!params && dict[key] === undefined && lang !== "en" && key.length < 400) {
      const hit = memo.get(key);
      if (hit !== undefined) {
        if (hit !== null) return hit;
      } else {
        for (const pt of patternsFor(lang)) {
          const m = key.match(pt.re);
          if (m) {
            let out = pt.value;
            pt.names.forEach((n, i) => (out = out.replaceAll(`{${n}}`, t(m[i + 1]) as string)));
            memo.set(key, out);
            return out;
          }
        }
        memo.set(key, null);
      }
    }
    if (!params && dict[key] === undefined && lang === "ar") {
      const d = localizeDateTokens(s);
      if (d !== s) return d;
    }
    if (params)
      for (const [k, v] of Object.entries(params))
        // text values (e.g. "bill" / "bills", statuses) are translated too; numbers and names pass through
        s = s.replaceAll(`{${k}}`, typeof v === "string" ? t(v) : String(v ?? ""));
    return s;
  }) as TFunction;
  return t;
}
