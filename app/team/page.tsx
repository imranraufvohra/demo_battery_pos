import type { Metadata } from "next";
import { redirect } from "next/navigation";
import PageHeader from "@/components/PageHeader";
import { createClient } from "@/lib/supabase/server";
import { can } from "@/lib/roles";
import { loadRoleInfo } from "@/lib/rolesServer";
import TeamClient, { type TeamMember } from "./TeamClient";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Team") };
}

export default async function TeamPage() {
  const t = await getT();
  const info = await loadRoleInfo();
  if (!can(info, "team.manage")) redirect("/");

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const { data, error } = await supabase.rpc("team_list");

  if (error) {
    return (
      <div className="card max-w-xl border-terminal/40 p-6">
        <h1 className="font-display text-3xl font-bold"><T>Team could not be loaded</T></h1>
        <p className="mt-3 text-lead"><T p={{ p: " " }}>{"Open Supabase, go to SQL Editor, and run{p}"}</T><code className="rounded bg-plate px-1.5 py-0.5 text-casing">16_roles_and_audit.sql</code>.
        </p>
        <p className="mt-3 text-sm text-lead"><T p={{ message: error.message }}>{"Details: {message}"}</T></p>
      </div>
    );
  }

  return (
    <div className="max-w-3xl">
      <PageHeader title={t("Team")} subtitle={t("Everyone who can sign in to PowerCell POS, and what each person may do.")} />
      <TeamClient members={(data ?? []) as TeamMember[]} myId={user?.id ?? ""} />
    </div>
  );
}
