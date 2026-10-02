import { BRAND } from "@/lib/brand";
import InstallAppButton from "@/components/InstallAppButton";

export const metadata = { title: "Start demo" };

export default async function DemoStart({ searchParams }: { searchParams: Promise<{ region?: string; error?: string }> }) {
  const sp = await searchParams;
  const site = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
  const demoEmail = process.env.DEMO_USER_EMAIL ?? "demo@makemystore.online";
  return (
    <main className="grid min-h-dvh place-items-center bg-[#1c2b33] p-6 text-white">
      <form action="/api/demo-login" method="post" className="w-full max-w-sm space-y-5 text-center">
        <h1 className="font-display text-3xl font-bold">{BRAND.name}</h1>
        <p className="text-white/70">Live demo with sample data. Do not enter real business information.</p>
        <input type="hidden" name="region" value={sp.region ?? ""} />
        {/* Looks like a normal login, but nothing is typed: the server signs the shared demo user in.
            The real password is never sent to the browser. */}
        <div className="space-y-2 text-left text-sm">
          <label className="block text-white/60">
            Email
            <input readOnly tabIndex={-1} value={demoEmail} className="mt-1 w-full rounded-xl border border-white/15 bg-white/10 px-3 py-2.5 text-white" />
          </label>
          <label className="block text-white/60">
            Password
            <input readOnly tabIndex={-1} type="password" value="demo-password" className="mt-1 w-full rounded-xl border border-white/15 bg-white/10 px-3 py-2.5 text-white" />
          </label>
        </div>
        {site && (
          <>
            <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer />
            <div className="cf-turnstile" data-sitekey={site} />
          </>
        )}
        {sp.error && <p className="text-amber-300">Could not start the demo. Please try again.</p>}
        <button className="w-full rounded-xl bg-amber-400 px-4 py-3 font-semibold text-black">Log in to demo</button>
        <div className="text-black"><InstallAppButton /></div>
      </form>
    </main>
  );
}
