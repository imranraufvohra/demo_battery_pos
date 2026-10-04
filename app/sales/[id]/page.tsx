import type { Metadata } from "next";
import { formatMoney } from "@/lib/format";
import { notFound } from "next/navigation";
import { loadInvoiceDocument } from "@/lib/invoiceDoc";
import { loadFbrStatus } from "@/lib/fbrStatusLoad";
import { createClient } from "@/lib/supabase/server";
import InvoiceDetail from "./InvoiceDetail";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Bill") };
}

const when = new Intl.DateTimeFormat("en-GB", {
  day: "numeric",
  month: "short",
  hour: "numeric",
  minute: "2-digit",
  hour12: true,
  timeZone: (process.env.NEXT_PUBLIC_TIMEZONE ?? "UTC"),
});

export default async function InvoicePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const doc = await loadInvoiceDocument(id);
  if (!doc) notFound();
  const fbr = await loadFbrStatus(doc.invoice.id);

  // Who made this bill, and who received each payment. If the Part 1 SQL has not been run yet,
  // the lookup simply fails and this small section is left out.
  const inv = doc.invoice as typeof doc.invoice & { created_by?: string | null };
  const pays = doc.payments as (typeof doc.payments[number] & { received_by?: string | null })[];
  const ids = [...new Set([inv.created_by, ...pays.map((p) => p.received_by)].filter((x): x is string => !!x))];
  let names: Record<string, string> = {};
  if (ids.length > 0) {
    const supabase = await createClient();
    const { data } = await supabase.rpc("user_display_names", { p_ids: ids });
    if (data && typeof data === "object") names = data as Record<string, string>;
  }
  const madeBy = inv.created_by ? names[inv.created_by] : undefined;

  return (
    <>
      <InvoiceDetail doc={doc} fbr={fbr} />
      {(madeBy || pays.some((p) => p.received_by && names[p.received_by])) && (
        <section className="card mt-4 p-5">
          <h2 className="font-display text-2xl font-semibold"><T>Who did this</T></h2>
          <ul className="mt-2 space-y-1 text-[15px]">
            {madeBy && (
              <li>
                <T>Bill made by</T> <b><T>{madeBy}</T></b>, <T>{when.format(new Date(inv.created_at))}</T>
              </li>
            )}
            {pays.map((p) =>
              p.received_by && names[p.received_by] ? (
                <li key={p.id}><T p={{ formatMoney: formatMoney(Number(p.amount)) }}>{"{formatMoney} received by"}</T> <b><T>{names[p.received_by]}</T></b>,{" "}
                  <T>{when.format(new Date(p.paid_at))}</T>
                </li>
              ) : null
            )}
          </ul>
          <p className="mt-2 text-sm text-lead"><T>The Owner can see every change in Activity log.</T></p>
        </section>
      )}
    </>
  );
}
