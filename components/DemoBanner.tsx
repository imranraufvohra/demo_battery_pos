import { BRAND } from "@/lib/brand";
import { DEMO_MODE } from "@/lib/modules";
import { getT } from "@/lib/i18n/server";

export default async function DemoBanner() {
  if (!DEMO_MODE) return null;
  const t = await getT();
  return (
    <div className="flex flex-wrap items-center justify-center gap-x-4 gap-y-1 bg-amber-400 px-3 py-1.5 text-center text-xs font-medium text-black">
      <span>{t("demo.banner")}</span>
      <a className="underline" target="_top" href={`${BRAND.contactUrl}?source=demo&vertical=battery`}>
        {t("demo.cta")}
      </a>
    </div>
  );
}
