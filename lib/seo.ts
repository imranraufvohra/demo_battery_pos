import { BRAND } from "@/lib/brand";

/** Public address of the demo. Override with NEXT_PUBLIC_SITE_URL if the domain changes. */
export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL ?? "https://demo.makemystore.online").replace(/\/$/, "");

/** Only the demo deployment should be found by search engines. Client builds of this app stay private. */
export const INDEXABLE = process.env.NEXT_PUBLIC_DEMO_MODE === "true";

export const DEMO_TITLE = "Car Battery Shop POS & Inventory Software: Free Live Demo";
export const DEMO_DESCRIPTION =
  "Try a live POS and inventory system built for car battery shops: fast billing, stock levels, warranty claims, old-battery scrap, customer credit and reports. No signup needed.";
export const DEMO_KEYWORDS = [
  "car battery shop POS",
  "battery shop software",
  "battery inventory management",
  "battery warranty tracking",
  "scrap battery tracking",
  "POS demo",
  "inventory software demo",
  BRAND.poweredBy,
];

export const DEMO_FEATURES = [
  "Fast billing with cash, card and credit (udhaar) sales",
  "Battery stock levels with low-stock alerts",
  "Warranty claims and charging jobs",
  "Old battery (scrap) buying and selling",
  "Customer and supplier ledgers",
  "Purchases, expenses and daily cash book reports",
  "AI assistant that answers questions about your shop",
  "Works offline and installs as an app on your phone",
];
