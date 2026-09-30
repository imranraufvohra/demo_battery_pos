export const BRAND = {
  name: process.env.NEXT_PUBLIC_BRAND_NAME ?? "PowerCell Batteries & Solar",
  shortName: process.env.NEXT_PUBLIC_BRAND_SHORT ?? "PowerCell POS",
  tagline: "Battery & solar shop management",
  themeColor: "#1c2b33",
  poweredBy: "MakeMyStore",
  websiteUrl: process.env.NEXT_PUBLIC_WEBSITE_URL ?? "https://www.makemystore.online",
  contactUrl: (process.env.NEXT_PUBLIC_WEBSITE_URL ?? "https://www.makemystore.online") + "/contact",
};
