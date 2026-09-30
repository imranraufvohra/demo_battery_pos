"use client";
import { useState } from "react";
import { DEMO_URL, DEMO_REGIONS } from "@/lib/demo";

/** Put <PosDemo /> right after <PageHeader> in app/pos-system/page.tsx. The iframe is created only after the click. */
export default function PosDemo() {
  const [region, setRegion] = useState<string>("us");
  const [device, setDevice] = useState<"phone" | "desktop">("desktop");
  const [open, setOpen] = useState(false);
  const src = `${DEMO_URL}/demo-start?region=${region}`;

  const launch = () => {
    if (typeof window !== "undefined" && window.innerWidth < 768) {
      window.open(src, "_blank", "noopener"); // phones: full screen is better than an iframe
      return;
    }
    setOpen(true);
  };

  return (
    <section className="border-b border-border">
      <div className="mx-auto max-w-content px-5 py-16 sm:px-8">
        <h2 className="font-display text-3xl font-semibold text-ink sm:text-4xl">
          Try it yourself: a real working battery and solar shop system
        </h2>
        <p className="mt-3 text-sm text-ink/70">
          Sample data only. Built for any business; this demo shows a battery and solar shop.
        </p>
        <div className="mt-6 flex flex-wrap items-center gap-2">
          {DEMO_REGIONS.map((r) => (
            <button key={r.id} onClick={() => setRegion(r.id)}
              className={`rounded-full border px-4 py-1.5 text-sm ${region === r.id ? "border-mint bg-mint text-white" : "border-border"}`}>
              {r.label}
            </button>
          ))}
          <button onClick={() => setDevice(device === "phone" ? "desktop" : "phone")} className="ml-2 text-sm underline">
            {device === "phone" ? "Desktop view" : "Phone view"}
          </button>
        </div>
        {!open ? (
          <button onClick={launch} className="mt-6 rounded-full bg-mint px-6 py-3.5 text-sm font-semibold text-white">
            Launch live demo
          </button>
        ) : (
          <div className="mt-6">
            <iframe
              title="MakeMyStore POS live demo"
              src={src}
              allow="clipboard-write"
              sandbox="allow-scripts allow-same-origin allow-forms allow-popups allow-downloads allow-modals"
              className="mx-auto h-[720px] rounded-2xl border border-border"
              style={{ width: device === "phone" ? 390 : "100%", maxWidth: "100%" }}
            />
            <a href={src} target="_blank" rel="noopener noreferrer" className="mt-3 inline-block text-sm underline">
              Open full screen
            </a>
          </div>
        )}
        <a href="/contact?source=demo&vertical=battery" className="mt-6 block text-sm font-semibold text-mint">
          Want this for your shop? Tell us about your business
        </a>
      </div>
    </section>
  );
}
