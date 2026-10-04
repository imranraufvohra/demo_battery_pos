import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import type { Invoice } from "@/lib/types";
import UdhaarClient from "./UdhaarClient";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Credit") };
}

export default async function UdhaarPage() {
  const supabase = await createClient();
  // Only bills that are not cancelled and still have money due. Oldest bill first.
  const [{ data, error }, customersRes] = await Promise.all([
    supabase
    .from("invoice_balances")
    .select("*")
    .neq("status", "Cancelled")
    .gt("due_total", 0)
    .order("invoice_date", { ascending: true })
    .order("created_at", { ascending: true })
    .limit(2000),
    // Saved customers, for the "Add credit" form.
    supabase.from("customers").select("id,name,phone").order("name", { ascending: true }).limit(3000),
  ]);

  if (error) {
    return (
      <div className="card max-w-xl border-terminal/40 p-6">
        <h1 className="font-display text-3xl font-bold"><T>Credit could not be loaded</T></h1>
        <p className="mt-3 text-lead"><T p={{ p: " " }}>{"The app is connected, but Supabase did not return the bills. Open Supabase, go to SQL Editor, and run{p}"}</T><code className="rounded bg-plate px-1.5 py-0.5 text-casing">03_invoices.sql</code>.
        </p>
        <p className="mt-3 text-sm text-lead"><T p={{ message: error.message }}>{"Details: {message}"}</T></p>
      </div>
    );
  }

  return <UdhaarClient
      serverInvoices={(data ?? []) as Invoice[]}
      customers={(customersRes.data ?? []) as { id: string; name: string; phone: string | null }[]}
    />;
}
