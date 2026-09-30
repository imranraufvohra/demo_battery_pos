import { BRAND } from "@/lib/brand";

export const metadata = { title: "Start demo" };

export default async function DemoStart({ searchParams }: { searchParams: Promise<{ region?: string; error?: string }> }) {
  const sp = await searchParams;
  const site = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
  return (
    <main className="grid min-h-dvh place-items-center bg-[#1c2b33] p-6 text-white">
      <form action="/api/demo-login" method="post" className="w-full max-w-sm space-y-5 text-center">
        <h1 className="font-display text-3xl font-bold">{BRAND.name}</h1>
        <p className="text-white/70">Live demo with sample data. Do not enter real business information.</p>
        <input type="hidden" name="region" value={sp.region ?? ""} />
        {site && (
          <>
            <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer />
            <div className="cf-turnstile" data-sitekey={site} />
          </>
        )}
        {sp.error && <p className="text-amber-300">Could not start the demo. Please try again.</p>}
        <button className="w-full rounded-xl bg-amber-400 px-4 py-3 font-semibold text-black">Start demo</button>
      </form>
    </main>
  );
}
