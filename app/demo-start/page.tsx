import type { Metadata } from "next";
import { BRAND } from "@/lib/brand";
import InstallAppButton from "@/components/InstallAppButton";
import { DEMO_DESCRIPTION, DEMO_FEATURES, DEMO_KEYWORDS, DEMO_TITLE, INDEXABLE, SITE_URL } from "@/lib/seo";
import DemoStartForm from "./DemoStartForm";

import { T } from "@/components/T";
const PAGE_URL = `${SITE_URL}/demo-start`;
// The full marketing page for this demo lives on the main site. Pointing the canonical there makes
// Google rank that page instead of this login screen, so the two don't compete for the same keywords.
const MAIN_PAGE_URL = `${BRAND.websiteUrl}/pos-system/battery-solar-shop`;

export const metadata: Metadata = {
  title: { absolute: `${DEMO_TITLE} | ${BRAND.poweredBy}` },
  description: DEMO_DESCRIPTION,
  keywords: DEMO_KEYWORDS,
  applicationName: BRAND.shortName,
  authors: [{ name: BRAND.poweredBy, url: BRAND.websiteUrl }],
  alternates: { canonical: MAIN_PAGE_URL },
  // The rest of the app is behind the demo login, so this start page is the one page worth indexing.
  robots: INDEXABLE
    ? { index: true, follow: true, googleBot: { index: true, follow: true, "max-image-preview": "large", "max-snippet": -1 } }
    : { index: false, follow: false },
  openGraph: {
    type: "website",
    url: PAGE_URL,
    siteName: BRAND.poweredBy,
    title: DEMO_TITLE,
    description: DEMO_DESCRIPTION,
    locale: "en_US",
  },
  twitter: { card: "summary_large_image", title: DEMO_TITLE, description: DEMO_DESCRIPTION },
};

const jsonLd = {
  "@context": "https://schema.org",
  "@type": "SoftwareApplication",
  name: `${BRAND.name} POS demo`,
  alternateName: BRAND.shortName,
  url: PAGE_URL,
  description: DEMO_DESCRIPTION,
  applicationCategory: "BusinessApplication",
  applicationSubCategory: "Point of sale and inventory management",
  operatingSystem: "Web, Android, iOS",
  featureList: DEMO_FEATURES,
  offers: { "@type": "Offer", price: "0", priceCurrency: "USD", description: "Free live demo with sample data" },
  publisher: { "@type": "Organization", name: BRAND.poweredBy, url: BRAND.websiteUrl },
};

export default async function DemoStart({ searchParams }: { searchParams: Promise<{ region?: string; error?: string }> }) {
  const sp = await searchParams;
  const site = process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY;
  const demoEmail = process.env.DEMO_USER_EMAIL ?? "demo@makemystore.online";
  return (
    <main className="grid min-h-dvh place-items-center bg-[#1c2b33] p-6 text-white">
      <script
        type="application/ld+json"
        // "<" is escaped so the JSON can never close the script tag early.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, "\\u003c") }}
      />
      <div className="flex w-full max-w-sm flex-col items-center gap-8 py-4">
        <DemoStartForm footer={<div className="text-black"><InstallAppButton /></div>}>
          <h1 className="font-display text-3xl font-bold">{BRAND.name}</h1>
          <p className="text-white/70"><T>Live demo of a car battery shop POS and inventory system. Sample data only, so do not enter real business information.</T></p>
          <input type="hidden" name="region" value={sp.region ?? ""} />
          {/* Looks like a normal login, but nothing is typed: the server signs the shared demo user in.
              The real password is never sent to the browser. */}
          <div className="space-y-2 text-start text-sm">
            <label className="block text-white/60">
              <T>Email</T>
              <input readOnly tabIndex={-1} value={demoEmail} className="mt-1 w-full rounded-xl border border-white/15 bg-white/10 px-3 py-2.5 text-white" />
            </label>
            <label className="block text-white/60">
              <T>Password</T>
              <input readOnly tabIndex={-1} type="password" value="demo-password" className="mt-1 w-full rounded-xl border border-white/15 bg-white/10 px-3 py-2.5 text-white" />
            </label>
          </div>
          {site && (
            <>
              <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer />
              <div className="cf-turnstile" data-sitekey={site} />
            </>
          )}
          {sp.error && <p className="text-amber-300"><T>Could not start the demo. Please try again.</T></p>}
        </DemoStartForm>

        {/* Crawlable text for search engines and a quick "what is this" for visitors. */}
        <section aria-labelledby="demo-features" className="w-full text-start text-sm text-white/60">
          <h2 id="demo-features" className="mb-2 font-display text-lg font-semibold text-white/80">
            <T>What you can try in this demo</T>
          </h2>
          <ul className="list-disc space-y-1 ps-5">
            {DEMO_FEATURES.map((f) => (
              <li key={f}><T>{f}</T></li>
            ))}
          </ul>
          <p className="mt-3"><T p={{ p: " " }}>{"Built by{p}"}</T><a className="underline hover:text-white" href={BRAND.websiteUrl} target="_top">
              <T>{BRAND.poweredBy}</T>
            </a><T p={{ p: " " }}>{"{p}for battery and solar shops."}</T></p>
        </section>
      </div>
    </main>
  );
}
