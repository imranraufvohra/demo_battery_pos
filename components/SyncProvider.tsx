"use client";

import { useEffect } from "react";
import { startAutoSync } from "@/lib/offline/sync";

/** Mounted once in app/layout.tsx, alongside RegisterSW. Renders nothing.
 *  Sync starts a few seconds after the page loads so it does not compete with the page's own requests. */
export default function SyncProvider() {
  useEffect(() => {
    const w = window as Window & {
      requestIdleCallback?: (cb: () => void, opts?: { timeout: number }) => number;
      cancelIdleCallback?: (id: number) => void;
    };
    const timer = window.setTimeout(() => {
      if (w.requestIdleCallback) w.requestIdleCallback(() => startAutoSync(), { timeout: 5000 });
      else startAutoSync();
    }, 3000);
    return () => window.clearTimeout(timer);
  }, []);
  return null;
}
