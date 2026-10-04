import type { Metadata } from "next";

import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Print") };
}

/** Print pages have no menus around them, so the paper shows only the bill. Signed-in access is enforced by middleware.ts. */
export default function PrintLayout({ children }: { children: React.ReactNode }) {
  return <div className="min-h-dvh">{children}</div>;
}
