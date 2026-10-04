import type { Metadata } from "next";
import { createClient } from "@/lib/supabase/server";
import type { ExpenseCategory, ExpenseDetails } from "@/lib/types";
import ExpensesClient from "./ExpensesClient";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Expenses") };
}

export default async function ExpensesPage() {
  const supabase = await createClient();
  const [expenses, categories] = await Promise.all([
    supabase
      .from("expense_details")
      .select("*")
      .order("expense_date", { ascending: false })
      .order("created_at", { ascending: false })
      .limit(1000),
    supabase.from("expense_categories").select("*").order("sort_order"),
  ]);

  if (expenses.error || categories.error) {
    return (
      <div className="card max-w-xl border-terminal/40 p-6">
        <h1 className="font-display text-3xl font-bold"><T>Expenses could not be loaded</T></h1>
        <p className="mt-3 text-lead"><T p={{ p: " " }}>{"Open Supabase, go to SQL Editor, and run{p}"}</T><code className="rounded bg-plate px-1.5 py-0.5 text-casing">14_expenses.sql</code>.
        </p>
        <p className="mt-3 text-sm text-lead"><T p={{ p: (expenses.error ?? categories.error)?.message }}>{"Details: {p}"}</T></p>
      </div>
    );
  }

  return (
    <ExpensesClient
      expenses={(expenses.data ?? []) as ExpenseDetails[]}
      categories={(categories.data ?? []) as ExpenseCategory[]}
    />
  );
}
