import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import type { PurchaseInvoice, SupplierBalance } from "@/lib/types";
import NewPayment from "./NewPayment";

import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Make payment") };
}

export default async function NewPaymentPage({
  searchParams,
}: {
  searchParams: Promise<{ supplier?: string; purchase?: string }>;
}) {
  const { supplier, purchase } = await searchParams;
  const supabase = await createClient();
  const [suppliers, duePurchases] = await Promise.all([
    supabase.from("supplier_balances").select("*").eq("is_active", true).order("name"),
    supabase
      .from("purchase_balances")
      .select("*")
      .neq("status", "Cancelled")
      .gt("due_total", 0)
      .order("invoice_date", { ascending: false }),
  ]);

  return (
    <NewPayment
      suppliers={(suppliers.data ?? []) as SupplierBalance[]}
      duePurchases={(duePurchases.data ?? []) as PurchaseInvoice[]}
      initialSupplierId={supplier ?? null}
      initialPurchaseId={purchase ?? null}
    />
  );
}
