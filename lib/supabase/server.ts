import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

/** Demo only: the demo runs inside an iframe on another site, so its login cookie must be SameSite=None. */
const demoCookie = (o: object | undefined) =>
  process.env.NEXT_PUBLIC_DEMO_MODE === "true" ? { ...(o ?? {}), sameSite: "none" as const, secure: true } : o;

export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, demoCookie(options))
            );
          } catch {
            // Called from a Server Component: safe to ignore, middleware refreshes the session.
          }
        },
      },
    }
  );
}
