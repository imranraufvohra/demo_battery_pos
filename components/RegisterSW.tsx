"use client";

import { useEffect } from "react";

export default function RegisterSW() {
  useEffect(() => {
    if (process.env.NODE_ENV !== "production") return;
    if (!("serviceWorker" in navigator)) return;
    if (window.self !== window.top) return; // inside the website iframe: no service worker

    const register = () => {
      navigator.serviceWorker.register("/sw.js").catch(() => {
        // Silent: PWA install/offline support is a progressive enhancement,
        // not something that should break the app if it fails.
      });
    };

    window.addEventListener("load", register);
    return () => window.removeEventListener("load", register);
  }, []);

  return null;
}
