import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import type { SupplierBalance } from "@/lib/types";
import SuppliersClient from "./SuppliersClient";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Suppliers") };
}

export default async function SuppliersPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("supplier_balances")
    .select("*")
    .order("name", { ascending: true });

  if (error) {
    return (
      <div className="card max-w-xl border-terminal/40 p-6">
        <h1 className="font-display text-3xl font-bold"><T>Suppliers could not be loaded</T></h1>
        <p className="mt-3 text-lead">
          <T>{"The app is connected, but Supabase did not return the supplier list. The most common reason is that the purchases tables have not been created yet. Open Supabase, go to SQL Editor, and run "}</T> <code className="rounded bg-plate px-1.5 py-0.5 text-casing">12_suppliers_purchases.sql</code><T p={{ p: " " }}>{"{p}then"}</T> <code className="rounded bg-plate px-1.5 py-0.5 text-casing">12b_supplier_save.sql</code>.
        </p>
        <p className="mt-3 text-sm text-lead"><T p={{ message: error.message }}>{"Details: {message}"}</T></p>
      </div>
    );
  }

  return <SuppliersClient suppliers={(data ?? []) as SupplierBalance[]} />;
}
