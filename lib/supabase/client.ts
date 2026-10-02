import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    // Demo only: the demo runs in an iframe on another site, so its cookie must be SameSite=None.
    process.env.NEXT_PUBLIC_DEMO_MODE === "true"
      ? { cookieOptions: { sameSite: "none", secure: true } }
      : undefined
  );
}
