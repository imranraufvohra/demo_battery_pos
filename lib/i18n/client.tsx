"use client";

import { createContext, useCallback, useContext, useMemo } from "react";
import { useRouter } from "next/navigation";
import { LANG_COOKIE, dirOf, type Lang } from "./config";
import { makeT, type TFunction } from "./translate";

type Ctx = { lang: Lang; dir: "ltr" | "rtl"; t: TFunction; setLang: (l: Lang) => void };

const I18nContext = createContext<Ctx>({
  lang: "en",
  dir: "ltr",
  t: makeT("en"),
  setLang: () => {},
});

/** Mounted once in app/layout.tsx with the language the server read from the cookie. */
export function I18nProvider({ lang, children }: { lang: Lang; children: React.ReactNode }) {
  const router = useRouter();

  const setLang = useCallback(
    (next: Lang) => {
      document.cookie = `${LANG_COOKIE}=${next}; path=/; max-age=31536000; samesite=lax`;
      document.documentElement.lang = next;
      document.documentElement.dir = dirOf(next);
      router.refresh(); // re-render server components in the new language
    },
    [router]
  );

  const value = useMemo<Ctx>(() => ({ lang, dir: dirOf(lang), t: makeT(lang), setLang }), [lang, setLang]);
  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export const useI18n = () => useContext(I18nContext);
export const useT = (): TFunction => useContext(I18nContext).t;
