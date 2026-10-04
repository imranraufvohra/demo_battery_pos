"use client";

import { FBR_LABEL, FBR_TONE, FBR_TONE_DARK, type FbrInfo } from "@/lib/fbrStatus";
import { useT } from "@/lib/i18n/client";

import { T } from "@/components/T";
/** Small coloured tag next to the payment tag: FBR waiting / sent / failed / unsure. Test bills say "(test)". */
export default function FbrBadge({ info, onDark }: { info: FbrInfo; onDark?: boolean }) {
  const t = useT();
  const tone = (onDark ? FBR_TONE_DARK : FBR_TONE)[info.status];
  const test = info.environment === "sandbox" ? " (test)" : "";
  return (
    <span
      className={`inline-flex rounded-full px-2.5 py-1 text-xs font-semibold ${tone}`}
      title={t(info.number ? t("FBR invoice number {n}", { n: info.number }) : undefined)}
    >
      <T>{FBR_LABEL[info.status]}</T>
      <T>{test}</T>
    </span>
  );
}
