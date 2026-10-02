import type { MetadataRoute } from "next";
import { INDEXABLE, SITE_URL } from "@/lib/seo";

/** Only the start page is public. Everything else sits behind the demo login. */
export default function sitemap(): MetadataRoute.Sitemap {
  if (!INDEXABLE) return [];
  return [{ url: `${SITE_URL}/demo-start`, changeFrequency: "monthly", priority: 1 }];
}
