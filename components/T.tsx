"use client";

import { useT } from "@/lib/i18n/client";

/**
 * Translated text for JSX: <T>Running low</T>, or <T>{someString}</T> for text that comes from
 * a variable (messages, labels, statuses). The English text is the key. Anything without an
 * Arabic entry (customer names, product models...) is shown unchanged.
 * Placeholders: <T p={{ n: count }}>{"{n} bills"}</T>.
 * Works inside server and client components alike.
 */
export function T({
  children,
  p,
}: {
  children?: string | null | false;
  p?: Record<string, unknown>;
}) {
  const t = useT();
  if (!children) return null;
  return <>{t(children, p)}</>;
}

export default T;

/** <option> only accepts plain text, so translated options use this wrapper instead of <T>. */
export function Opt({ children, ...rest }: React.OptionHTMLAttributes<HTMLOptionElement>) {
  const t = useT();
  const text = Array.isArray(children) ? children.join("") : children;
  return <option {...rest}>{typeof text === "string" ? t(text) : text}</option>;
}
