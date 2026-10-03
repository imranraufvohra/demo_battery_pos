export type Lang = "en" | "ar";

export const LANGS: Lang[] = ["en", "ar"];
export const DEFAULT_LANG: Lang = "en";
export const LANG_COOKIE = "lang";

export const LANG_NAME: Record<Lang, string> = { en: "English", ar: "العربية" };

export function isLang(v: unknown): v is Lang {
  return v === "en" || v === "ar";
}

export function dirOf(lang: Lang): "ltr" | "rtl" {
  return lang === "ar" ? "rtl" : "ltr";
}
