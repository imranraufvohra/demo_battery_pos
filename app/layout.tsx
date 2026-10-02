import type { Metadata, Viewport } from "next";
import { Barlow, Barlow_Condensed } from "next/font/google";
import { BRAND } from "@/lib/brand";
import { SITE_URL } from "@/lib/seo";
import RegisterSW from "@/components/RegisterSW";
import SyncProvider from "@/components/SyncProvider";
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

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`${barlow.variable} ${barlowCondensed.variable}`}>
      <body className="font-sans text-casing antialiased">
        {children}
        <RegisterSW />
        <SyncProvider />
      </body>
    </html>
  );
}
