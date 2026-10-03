import type { Metadata, Viewport } from "next";
import { Barlow, Barlow_Condensed, Noto_Sans_Arabic } from "next/font/google";
import { BRAND } from "@/lib/brand";
import { SITE_URL } from "@/lib/seo";
import RegisterSW from "@/components/RegisterSW";
import SyncProvider from "@/components/SyncProvider";
import { I18nProvider } from "@/lib/i18n/client";
import { dirOf } from "@/lib/i18n/config";
import { getLang } from "@/lib/i18n/server";
import "./globals.css";

const barlow = Barlow({
  subsets: ["latin"],
  weight: ["400", "500", "600"],
  variable: "--font-barlow",
  display: "swap",
});

const barlowCondensed = Barlow_Condensed({
  subsets: ["latin"],
  weight: ["600", "700"],
  variable: "--font-barlow-condensed",
  display: "swap",
});

// Arabic script font, used instead of Barlow when the UI language is Arabic (see globals.css).
const notoArabic = Noto_Sans_Arabic({
  subsets: ["arabic"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-arabic",
  display: "swap",
});

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: BRAND.shortName, template: `%s | ${BRAND.shortName}` },
  description: BRAND.tagline,
  // Private by default: everything inside the app is behind a login. /demo-start opts in to indexing.
  robots: { index: false, follow: false },
  manifest: "/manifest.webmanifest",
  icons: {
    icon: "/icon.svg",
    apple: "/icons/apple-touch-icon.png",
  },
  appleWebApp: {
    capable: true,
    statusBarStyle: "black-translucent",
    title: BRAND.shortName,
  },
};

export const viewport: Viewport = {
  themeColor: "#1c2b33",
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export default async function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const lang = await getLang();
  return (
    <html
      lang={lang}
      dir={dirOf(lang)}
      className={`${barlow.variable} ${barlowCondensed.variable} ${notoArabic.variable}`}
    >
      <body className="font-sans text-casing antialiased">
        <I18nProvider lang={lang}>
          {children}
          <RegisterSW />
          <SyncProvider />
        </I18nProvider>
      </body>
    </html>
  );
}
