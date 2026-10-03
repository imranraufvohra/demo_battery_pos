import { NextResponse, type NextRequest } from "next/server";
import { createClient } from "@/lib/supabase/server";

/** Demo only: signs the shared demo user in on the server so the session cookie is set server-side. */
export async function POST(req: NextRequest) {
  if (process.env.NEXT_PUBLIC_DEMO_MODE !== "true") return new NextResponse("Not found", { status: 404 });
  const form = await req.formData();
  const fail = () => NextResponse.redirect(new URL("/demo-start?error=1", req.url), 303);

  const secret = process.env.TURNSTILE_SECRET_KEY;
  if (secret) {
    const token = String(form.get("cf-turnstile-response") ?? "");
    let ok = false;
    try {
      const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
        method: "POST",
        body: new URLSearchParams({ secret, response: token }),
        signal: AbortSignal.timeout(4000), // never hang the login if Cloudflare is slow
      });
      const j = (await r.json()) as { success?: boolean };
      ok = !!j.success;
    } catch {
      ok = false;
    }
    if (!ok) return fail();
  }

  const email = process.env.DEMO_USER_EMAIL;
  const password = process.env.DEMO_USER_PASSWORD;
  if (!email || !password) return fail();

  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) return fail();
  return NextResponse.redirect(new URL("/", req.url), 303);
}
