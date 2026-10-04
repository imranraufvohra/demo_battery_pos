import type { Metadata } from "next";
import { redirect } from "next/navigation";
import PageHeader from "@/components/PageHeader";
import { createClient } from "@/lib/supabase/server";
import { can } from "@/lib/roles";
import { loadRoleInfo } from "@/lib/rolesServer";
import ActivityClient, { type Person } from "./ActivityClient";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Activity log") };
}

export default async function ActivityPage() {
  const t = await getT();
  const info = await loadRoleInfo();
  if (!can(info, "activity.view")) redirect("/");

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("team_list");

  if (error) {
    return (
      <div className="card max-w-xl border-terminal/40 p-6">
        <h1 className="font-display text-3xl font-bold"><T>Activity log could not be loaded</T></h1>
        <p className="mt-3 text-lead"><T p={{ p: " " }}>{"Open Supabase, go to SQL Editor, and run{p}"}</T><code className="rounded bg-plate px-1.5 py-0.5 text-casing">16_roles_and_audit.sql</code>.
        </p>
        <p className="mt-3 text-sm text-lead"><T p={{ message: error.message }}>{"Details: {message}"}</T></p>
      </div>
    );
  }

  const people: Person[] = ((data ?? []) as { user_id: string; full_name: string; email: string | null }[]).map((m) => ({
    id: m.user_id,
    name: m.full_name || (m.email ?? "Unknown"),
  }));

  return (
    <div className="max-w-4xl">
      <PageHeader
        title={t("Activity log")}
        subtitle={t("Every add, change and delete in the app: who did it, when, and what changed.")}
      />
      <ActivityClient people={people} />
    </div>
  );
}
