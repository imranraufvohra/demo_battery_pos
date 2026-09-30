export const DEMO_URL = process.env.NEXT_PUBLIC_POS_DEMO_URL ?? "https://demo.makemystore.online";
export const DEMO_REGIONS = [
  { id: "uae", label: "UAE (AED)" },
  { id: "uk", label: "UK (GBP)" },
  { id: "us", label: "USA (USD)" },
] as const;
