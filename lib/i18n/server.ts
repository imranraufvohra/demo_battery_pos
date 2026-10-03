import { cookies } from "next/headers";
import { DEFAULT_LANG, LANG_COOKIE, isLang, type Lang } from "./config";
import { makeT, type TFunction } from "./translate";

/** Current UI language, from the "lang" cookie. Server components and layouts only. */
export async function getLang(): Promise<Lang> {
  const v = (await cookies()).get(LANG_COOKIE)?.value;
  return isLang(v) ? v : DEFAULT_LANG;
}

export async function getT(): Promise<TFunction> {
  return makeT(await getLang());
}
