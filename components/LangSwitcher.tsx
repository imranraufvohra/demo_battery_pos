"use client";

import { LANGS, LANG_NAME } from "@/lib/i18n/config";
import { useI18n } from "@/lib/i18n/client";

/**
 * English | العربية toggle. variant "pill" is the compact one for the top bar and login screen,
 * "row" is the full-width one on the More page.
 */
export default function LangSwitcher({
  variant = "pill",
  className = "",
}: {
  variant?: "pill" | "row";
  className?: string;
}) {
  const { lang, setLang, t } = useI18n();
  return (
    <div
      role="group"
      aria-label={t("common.language")}
      className={`inline-flex rounded-full bg-white p-0.5 shadow-sm ring-1 ring-line/70 ${
        variant === "row" ? "w-full" : ""
      } ${className}`}
    >
      {LANGS.map((l) => {
        const active = l === lang;
        return (
          <button
            key={l}
            type="button"
            lang={l}
            aria-pressed={active}
            onClick={() => !active && setLang(l)}
            className={`min-h-9 rounded-full px-3 text-sm font-semibold transition-colors ${
              variant === "row" ? "flex-1" : ""
            } ${active ? "bg-casing text-white" : "text-lead hover:text-casing"}`}
          >
            {LANG_NAME[l]}
          </button>
        );
      })}
    </div>
  );
}
