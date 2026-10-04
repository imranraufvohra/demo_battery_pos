"use client";

import { useEffect } from "react";
import Link from "next/link";
import { useSearchParams } from "next/navigation";
import Icon from "@/components/Icons";
import { formatPhone } from "@/lib/customers";
import { formatRs } from "@/lib/format";
import { formatDay } from "@/lib/invoices";
import type { ScrapSaleSlipDocument } from "@/lib/scrapBatteryDoc";

import { T } from "@/components/T";
export default function ScrapSaleSlipView({ doc }: { doc: ScrapSaleSlipDocument }) {
  const { sale, batteries, seller } = doc;
  const params = useSearchParams();
  const totalQty = batteries.reduce((sum, b) => sum + b.quantity, 0);

  useEffect(() => {
    if (params.get("auto") !== "1") return;
    const t = setTimeout(() => window.print(), 400);
    return () => clearTimeout(t);
  }, [params]);

  return (
    <div className="px-3 pb-10 pt-4 sm:px-6 print:p-0">
      <div className="no-print mx-auto mb-4 flex max-w-[148mm] flex-wrap items-center gap-2">
        <Link href="/scrap" className="btn btn-quiet">
          <Icon name="back" className="h-5 w-5" /> <T>Back</T>
        </Link>
        <button type="button" onClick={() => window.print()} className="btn btn-primary">
          <Icon name="printer" className="h-5 w-5" /> <T>Print</T>
        </button>
        <p className="w-full text-sm text-lead"><T>To save a PDF from the print box, choose Save as PDF as the printer.</T></p>
      </div>

      <article className="mx-auto max-w-[148mm] rounded-lg border border-line bg-white p-5 text-[13px] leading-snug shadow-card sm:p-[10mm] print:max-w-none print:rounded-none print:border-0 print:p-0 print:shadow-none">
        <header className="flex flex-wrap items-start justify-between gap-4 border-b-2 border-casing pb-4">
          <div className="min-w-0">
            <h1 className="font-display text-2xl font-bold leading-none">{seller.business_name}</h1>
            {seller.address && <p className="mt-1.5">{seller.address}</p>}
            {seller.phone && <p className="mt-0.5 text-lead">{formatPhone(seller.phone)}</p>}
          </div>
          <div className="text-end">
            <p className="font-display text-2xl font-bold leading-none"><T>Scrap Sale Slip</T></p>
            <p className="mt-1 text-xs font-semibold uppercase tracking-wide text-terminal-deep"><T>Not a tax invoice</T></p>
            <p className="mt-1.5 text-base font-semibold tabular-nums">{sale.sale_number}</p>
            <p className="tabular-nums text-lead"><T>{formatDay(sale.sale_date)}</T></p>
          </div>
        </header>

        <section className="mt-4">
          <p className="text-[11px] font-bold uppercase tracking-widest text-lead"><T>Buyer</T></p>
          <p className="mt-1 text-base font-bold">{sale.buyer_name}</p>
          {sale.buyer_phone && <p>{formatPhone(sale.buyer_phone)}</p>}
        </section>

        <table className="mt-5 w-full text-start">
          <thead>
            <tr className="border-b-2 border-casing text-[11px] font-bold uppercase tracking-widest text-lead">
              <th className="py-1.5 pe-2"><T>Intake #</T></th>
              <th className="py-1.5 pe-2"><T>Battery</T></th>
              <th className="py-1.5 pe-2 text-end"><T>Qty</T></th>
            </tr>
          </thead>
          <tbody>
            {batteries.length === 0 ? (
              <tr>
                <td colSpan={3} className="py-2 text-lead">
                  <T>No individual battery records are linked to this lot.</T>
                </td>
              </tr>
            ) : (
              batteries.map((b) => (
                <tr key={b.id} className="border-b border-line/80">
                  <td className="py-1.5 pe-2 tabular-nums">{b.intake_number}</td>
                  <td className="py-1.5 pe-2">
                    {b.brand} {b.model}
                    {b.battery_number ? ` · ${b.battery_number}` : ""}
                  </td>
                  <td className="py-1.5 pe-2 text-end tabular-nums">{b.quantity}</td>
                </tr>
              ))
            )}
          </tbody>
          {batteries.length > 0 && (
            <tfoot>
              <tr className="border-t-2 border-casing font-semibold">
                <td className="py-1.5 pe-2" colSpan={2}>
                  <T>Total batteries</T>
                </td>
                <td className="py-1.5 pe-2 text-end tabular-nums">{totalQty}</td>
              </tr>
            </tfoot>
          )}
        </table>

        <div className="mt-4 flex justify-end">
          <dl className="w-64 space-y-1 break-inside-avoid">
            <div className="flex justify-between">
              <dt className="text-lead"><T>Total weight</T></dt>
              <dd className="tabular-nums"><T p={{ toLocaleString: sale.total_weight_kg.toLocaleString("en-US", { maximumFractionDigits: 2 }) }}>{"{toLocaleString} kg"}</T></dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-lead"><T>Rate per kg</T></dt>
              <dd className="tabular-nums">{formatRs(sale.rate_per_kg)}</dd>
            </div>
            <div className="flex justify-between border-t border-line pt-1 text-base font-bold">
              <dt><T>Total</T></dt>
              <dd className="tabular-nums">{formatRs(sale.total_amount)}</dd>
            </div>
          </dl>
        </div>

        {sale.note && (
          <p className="mt-4 break-inside-avoid rounded-lg bg-plate px-3 py-2.5 text-[12px]"><T p={{ note: sale.note }}>{"Note: {note}"}</T></p>
        )}

        <p className="mt-6 text-center text-lead"><T>Thank you for your business.</T></p>
      </article>
    </div>
  );
}
