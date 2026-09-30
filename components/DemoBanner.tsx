import { BRAND } from "@/lib/brand";
import { DEMO_MODE } from "@/lib/modules";

export default function DemoBanner() {
  if (!DEMO_MODE) return null;
  return (
    <div className="flex flex-wrap items-center justify-center gap-x-4 gap-y-1 bg-amber-400 px-3 py-1.5 text-center text-xs font-medium text-black">
      <span>Demo with sample data. Resets every hour.</span>
      <a className="underline" target="_top" href={`${BRAND.contactUrl}?source=demo&vertical=battery`}>
        Get this for my business
      </a>
    </div>
  );
}
