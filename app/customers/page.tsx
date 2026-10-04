import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import type { Customer } from "@/lib/types";
import CustomersClient from "./CustomersClient";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Customers") };
}

export default async function CustomersPage() {
  const supabase = await createClient();
  const { data, error } = await supabase
    .from("customers")
    .select("*")
    .order("name", { ascending: true });

  if (error) {
    return (
      <div className="card max-w-xl border-terminal/40 p-6">
        <h1 className="font-display text-3xl font-bold"><T>Customers could not be loaded</T></h1>
        <p className="mt-3 text-lead"><T p={{ p: " " }}>{"The app is connected, but Supabase did not return the customer list. The most common reason is that the database table has not been created yet. Open Supabase, go to SQL Editor, and run{p}"}</T><code className="rounded bg-plate px-1.5 py-0.5 text-casing">02_customers.sql</code>.
        </p>
        <p className="mt-3 text-sm text-lead"><T p={{ message: error.message }}>{"Details: {message}"}</T></p>
      </div>
    );
  }

  return <CustomersClient customers={(data ?? []) as Customer[]} />;
}
