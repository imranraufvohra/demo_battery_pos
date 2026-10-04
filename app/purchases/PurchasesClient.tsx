"use client";

import { useEffect, useMemo, useState } from "react";
import { useRoleInfo } from "@/components/RoleProvider";
import { can } from "@/lib/roles";
import Link from "next/link";
import { useRouter } from "next/navigation";
import Icon from "@/components/Icons";
import PageHeader from "@/components/PageHeader";
import Toast from "@/components/Toast";
import { formatRs } from "@/lib/format";
import { formatDay } from "@/lib/invoices";
import { friendlyPurchaseError, purchaseMatches } from "@/lib/purchases";
import { checkRealConnectivity } from "@/lib/offline/net";
import { getBrowserClient } from "@/lib/supabase/lazy";
import type { PurchaseInvoice } from "@/lib/types";
import PurchasePayBadge from "./PayBadge";

import { T } from "@/components/T";
import { useT } from "@/lib/i18n/client";
type Filter = "all" | "due" | "paid";

const TABS: { value: Filter; label: string }[] = [
  { value: "all", label: "All" },
  { value: "due", label: "We still owe" },
  { value: "paid", label: "Paid" },
];

export default function PurchasesClient({
  purchases: serverPurchases,
  supplierNames,
  initialFilter,
}: {
  purchases: PurchaseInvoice[];
  supplierNames: Record<string, string>;
  initialFilter: Filter;
}) {
  const tt = useT();
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState<Filter>(initialFilter);
  const [purchases, setPurchases] = useState(serverPurchases);
  useEffect(() => setPurchases(serverPurchases), [serverPurchases]);

  const roleInfo = useRoleInfo();
  const canManage = can(roleInfo, "purchases.manage");
  const [target, setTarget] = useState<PurchaseInvoice | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  const [toast, setToast] = useState<string | null>(null);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 3500);
    return () => clearTimeout(t);
  }, [toast]);

  function askCancel(p: PurchaseInvoice) {
    setReason("");
    setCancelError(null);
    setTarget(p);
  }

  async function confirmCancel() {
    if (!target || busy) return;
    if (!reason.trim()) {
      setCancelError("Say why this bill is being cancelled -- it's kept with the bill for the record.");
      return;
    }
    setBusy(true);
    setCancelError(null);

    const online = await checkRealConnectivity();
    if (!online) {
      setCancelError("Cancelling a purchase needs a connection, so stock can be reversed correctly. Try again once you're back online.");
      setBusy(false);
      return;
    }

    try {
      const supabase = await getBrowserClient();
      const { error } = await supabase.rpc("cancel_purchase", { p_purchase_id: target.id, p_reason: reason.trim() });
      if (error) {
        setCancelError(friendlyPurchaseError(error));
        setBusy(false);
        return;
      }
      setToast(`${target.purchase_number} cancelled.`);
      setTarget(null);
      setBusy(false);
      router.refresh();
    } catch {
      setCancelError("The connection dropped. Refresh this page to see if it was cancelled before you try again.");
      setBusy(false);
    }
  }

  const shown = useMemo(
    () =>
      purchases.filter((p) => {
        const name = supplierNames[p.supplier_id] ?? "";
        if (!purchaseMatches(p, name, query)) return false;
        if (filter === "due") return p.status !== "Cancelled" && p.due_total > 0;
        if (filter === "paid") return p.status !== "Cancelled" && p.due_total <= 0;
        return true;
      }),
    [purchases, supplierNames, query, filter]
  );

  const totalShown = shown.filter((p) => p.status !== "Cancelled").reduce((s, p) => s + p.total_value, 0);
  const dueShown = shown.filter((p) => p.status !== "Cancelled").reduce((s, p) => s + p.due_total, 0);

  return (
    <div>
      <PageHeader
        title={tt("Purchases")}
        subtitle={purchases.length === 0 ? "Stock you receive from suppliers will appear here." : `${purchases.length} purchase bills`}
        action={
          canManage && (
<Link href="/purchases/new" className="btn btn-primary">
            <Icon name="plus" className="h-5 w-5" /> <T>Receive stock</T>
          </Link>
)
        }
      />

      {purchases.length === 0 ? (
        <section className="card anim-rise mt-6 px-6 py-12 text-center">
          <span className="mx-auto inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-focus/10 text-focus">
            <Icon name="truck" className="h-7 w-7" />
          </span>
          <h2 className="mt-4 font-display text-3xl font-semibold"><T>No purchase bills yet</T></h2>
          <p className="mx-auto mt-2 max-w-md text-lead">
            <T>Record stock as it comes in from a supplier -- quantities and cost update together, in one save.</T>
          </p>
          {canManage && (
<Link href="/purchases/new" className="btn btn-primary mt-6">
            <T>Receive first stock</T>
          </Link>
)}
        </section>
      ) : (
        <>
          <div className="anim-rise mt-6 space-y-3">
            <div className="relative sm:max-w-md">
              <label htmlFor="purchase-search" className="sr-only">
                <T>Search purchase bills</T>
              </label>
              <Icon name="search" className="pointer-events-none absolute start-3.5 top-1/2 h-5 w-5 -translate-y-1/2 text-lead" />
              <input
                id="purchase-search"
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder={tt("Search bill no., supplier, or their invoice no.")}
                className="input ps-11"
              />
            </div>
            <div className="no-scrollbar -mx-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:px-0">
              {TABS.map((t) => (
                <button
                  key={t.value}
                  type="button"
                  onClick={() => setFilter(t.value)}
                  aria-pressed={filter === t.value}
                  className={`shrink-0 rounded-full border px-4 py-2 text-[15px] font-medium transition-colors ${
                    filter === t.value
                      ? "border-casing bg-casing text-white shadow-sm"
                      : "border-line bg-white text-lead hover:border-lead/40 hover:text-casing"
                  }`}
                >
                  <T>{t.label}</T>
                </button>
              ))}
            </div>
          </div>

          {shown.length === 0 ? (
            <div className="card mt-4 px-6 py-12 text-center">
              <p className="font-display text-2xl font-semibold"><T>Nothing matches</T></p>
              <p className="mt-2 text-lead"><T>Try a different search, or a different tab.</T></p>
            </div>
          ) : (
            <>
              <dl className="anim-rise mt-4 grid grid-cols-2 gap-3 sm:max-w-md">
                <div className="card p-3.5">
                  <dt className="text-xs text-lead sm:text-sm"><T>Total shown</T></dt>
                  <dd className="font-display text-xl font-semibold tabular-nums sm:text-2xl">{formatRs(totalShown)}</dd>
                </div>
                <div className={`card p-3.5 ${dueShown > 0 ? "border-terminal/30 bg-terminal/5" : ""}`}>
                  <dt className="text-xs text-lead sm:text-sm"><T>Still owed</T></dt>
                  <dd className={`font-display text-xl font-semibold tabular-nums sm:text-2xl ${dueShown > 0 ? "text-terminal-deep" : ""}`}>
                    {formatRs(dueShown)}
                  </dd>
                </div>
              </dl>

              {/* Tablet/desktop table */}
              <div className="card anim-rise mt-4 hidden overflow-hidden md:block">
                <table className="w-full text-start text-[15px]">
                  <thead className="border-b border-line bg-plate/60 text-xs uppercase tracking-[0.1em] text-lead">
                    <tr>
                      <th className="px-5 py-3 font-medium"><T>Bill</T></th>
                      <th className="px-3 py-3 font-medium"><T>Date</T></th>
                      <th className="px-3 py-3 font-medium"><T>Supplier</T></th>
                      <th className="px-3 py-3 text-end font-medium"><T>Total</T></th>
                      <th className="px-3 py-3 text-end font-medium"><T>Due</T></th>
                      <th className="px-5 py-3 font-medium"><T>Status</T></th>
                      <th className="px-3 py-3 text-end font-medium">
                        <span className="sr-only"><T>Cancel</T></span>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-line/60">
                    {shown.map((p) => (
                      <tr key={p.id} className="transition-colors hover:bg-plate/50">
                        <td className="px-5 py-3.5">
                          <Link href={`/purchases/${p.id}`} className="font-semibold text-focus hover:underline">
                            {p.purchase_number}
                          </Link>
                          {p.supplier_invoice_number && (
                            <div className="text-sm text-lead"><T p={{ supplier_invoice_number: p.supplier_invoice_number }}>{"Inv {supplier_invoice_number}"}</T></div>
                          )}
                        </td>
                        <td className="px-3 py-3.5 tabular-nums text-lead"><T>{formatDay(p.invoice_date)}</T></td>
                        <td className="max-w-[16rem] truncate px-3 py-3.5 font-medium">
                          <T>{supplierNames[p.supplier_id] ?? "Unknown supplier"}</T>
                        </td>
                        <td className="px-3 py-3.5 text-end font-semibold tabular-nums">{formatRs(p.total_value)}</td>
                        <td
                          className={`px-3 py-3.5 text-end tabular-nums ${
                            p.status !== "Cancelled" && p.due_total > 0 ? "font-semibold text-terminal-deep" : "text-lead"
                          }`}
                        >
                          <T>{p.status !== "Cancelled" && p.due_total > 0 ? formatRs(p.due_total) : "-"}</T>
                        </td>
                        <td className="px-5 py-3.5">
                          <PurchasePayBadge tag={p.payment_tag} status={p.status} />
                        </td>
                        <td className="px-3 py-3.5 text-end">
                          {p.status !== "Cancelled" && canManage && (
                            <button
                              type="button"
                              onClick={() => askCancel(p)}
                              aria-label={`Cancel bill ${p.purchase_number}`}
                              title={tt("Cancel bill")}
                              className="inline-flex h-10 w-10 items-center justify-center rounded-full text-lead hover:bg-terminal/10 hover:text-terminal-deep"
                            >
                              <Icon name="x" className="h-5 w-5" />
                            </button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Phone cards */}
              <ul className="mt-4 space-y-2.5 md:hidden">
                {shown.map((p) => (
                  <li key={p.id} className="flex items-stretch gap-2">
                    <Link href={`/purchases/${p.id}`} className="card card-hover flex min-w-0 flex-1 items-center gap-3 p-4">
                      <span className="min-w-0 flex-1">
                        <span className="truncate font-semibold"><T>{supplierNames[p.supplier_id] ?? "Unknown supplier"}</T></span>
                        <span className="mt-0.5 block text-sm text-lead">
                          {p.purchase_number} · <T>{formatDay(p.invoice_date)}</T>
                        </span>
                        <span className="mt-1.5 block">
                          <PurchasePayBadge tag={p.payment_tag} status={p.status} />
                        </span>
                      </span>
                      <span className="text-end">
                        <span className="block font-display text-2xl font-semibold leading-none tabular-nums">{formatRs(p.total_value)}</span>
                        {p.status !== "Cancelled" && p.due_total > 0 && (
                          <span className="mt-1 block text-sm font-semibold tabular-nums text-terminal-deep"><T p={{ formatRs: formatRs(p.due_total) }}>{"{formatRs} due"}</T></span>
                        )}
                      </span>
                      <Icon name="chevron" className="h-4 w-4 text-lead/60" />
                    </Link>
                    {p.status !== "Cancelled" && canManage && (
                      <button
                        type="button"
                        onClick={() => askCancel(p)}
                        aria-label={`Cancel bill ${p.purchase_number}`}
                        className="card inline-flex w-12 shrink-0 items-center justify-center text-lead hover:bg-terminal/10 hover:text-terminal-deep"
                      >
                        <Icon name="x" className="h-5 w-5" />
                      </button>
                    )}
                  </li>
                ))}
              </ul>
              {purchases.length >= 1000 && <p className="mt-3 text-sm text-lead"><T>Showing the latest 1,000 bills.</T></p>}
            </>
          )}
        </>
      )}

      {target && (
        <div className="anim-fade fixed inset-0 z-50 flex items-center justify-center bg-casing/60 p-4">
          <div role="alertdialog" aria-modal="true" aria-labelledby="cancel-title" className="anim-pop w-full max-w-md rounded-3xl bg-white p-6 shadow-2xl">
            <h2 id="cancel-title" className="font-display text-2xl font-bold"><T p={{ purchase_number: target.purchase_number }}>{"Cancel {purchase_number}?"}</T></h2>
            <p className="mt-2 text-lead"><T p={{ formatRs: formatRs(target.total_value), p: " ", supplier: supplierNames[target.supplier_id] ?? "this supplier" }}>{"This reverses the stock this bill added ({formatRs} from{p}{supplier}). It's refused if any of the stock has already been sold. Any payment already made stays recorded, as an advance. This cannot be undone."}</T></p>
            <label htmlFor="cancel-reason" className="mt-4 block text-sm font-medium">
              <T>Reason</T>
            </label>
            <input
              id="cancel-reason"
              type="text"
              autoFocus
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder={tt("e.g. Entered by mistake, wrong supplier")}
              className="input mt-1.5"
            />
            {cancelError && (
              <p role="alert" className="mt-4 rounded-xl bg-terminal/10 px-3 py-2 text-sm text-terminal-deep">
                <T>{cancelError}</T>
              </p>
            )}
            <div className="mt-6 flex justify-end gap-3">
              <button type="button" onClick={() => setTarget(null)} disabled={busy} className="btn btn-quiet">
                <T>Keep it</T>
              </button>
              <button type="button" onClick={confirmCancel} disabled={busy} className="btn btn-danger">
                <T>{busy ? "Cancelling" : "Cancel bill"}</T>
              </button>
            </div>
          </div>
        </div>
      )}

      <Toast message={toast} />
    </div>
  );
}
