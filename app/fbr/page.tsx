import type { Metadata } from "next";
import { redirect } from "next/navigation";
import PageHeader from "@/components/PageHeader";
import { createClient } from "@/lib/supabase/server";
import { can } from "@/lib/roles";
import { loadRoleInfo } from "@/lib/rolesServer";
import { FBR_KINDS, type FbrKind } from "@/lib/fbr";
import { loadFbrReadiness } from "@/lib/fbrHomeLoad";
import { isReadyForGoLive } from "@/lib/fbrReadiness";
import FbrListsClient from "./FbrListsClient";

import { T } from "@/components/T";
import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("FBR lists") };
}

export default async function FbrPage() {
  const t = await getT();
  const info = await loadRoleInfo();
  if (!can(info, "team.manage")) redirect("/");

  const supabase = await createClient();
  const readiness = await loadFbrReadiness();
  const [profile, heartbeat, ...counts] = await Promise.all([
    supabase.from("business_profile").select("business_name,ntn,province,fbr_enabled,fbr_environment,prices_include_tax").maybeSingle(),
    supabase.from("fbr_heartbeat").select("last_seen").maybeSingle(),
    ...FBR_KINDS.map((k) => supabase.from("fbr_reference").select("code", { count: "exact", head: true }).eq("kind", k.kind)),
  ]);

  if (profile.error || (profile.data && !("fbr_enabled" in profile.data))) {
    return (
      <div className="card max-w-xl border-terminal/40 p-6">
        <h1 className="font-display text-3xl font-bold"><T>FBR setup could not be loaded</T></h1>
        <p className="mt-3 text-lead">
          <T>Open Supabase, go to SQL Editor, and run</T> <code className="rounded bg-plate px-1.5 py-0.5 text-casing">18_fbr.sql</code> <T p={{ p: " " }}>{"and then{p}"}</T><code className="rounded bg-plate px-1.5 py-0.5 text-casing">19_fbr_d2_d3.sql</code>.
        </p>
        {profile.error && <p className="mt-3 text-sm text-lead"><T p={{ message: profile.error.message }}>{"Details: {message}"}</T></p>}
      </div>
    );
  }

  const loaded: Record<string, number> = {};
  FBR_KINDS.forEach((k, i) => (loaded[k.kind] = counts[i].count ?? 0));

  return (
    <div className="max-w-3xl">
      <PageHeader title={t("FBR lists")} subtitle={t("The lists FBR uses. Bills and items are checked against them.")} />

      {readiness && (
        <section className="card mb-5 p-5" aria-label={t("Go-live readiness")}>
          <div className="flex items-center justify-between gap-3">
            <h2 className="font-display text-xl font-semibold"><T>Go-live readiness</T></h2>
            <span
              className={`rounded-full px-3 py-1 text-sm font-semibold ${
                readiness.environment === "production" ? "bg-cell/20 text-cell-deep" : "bg-plate text-lead"
              }`}
            >
              <T>{readiness.environment === "production" ? "PRODUCTION" : "Sandbox"}</T>
            </span>
          </div>
          <p className="mt-1 text-sm text-lead">
            <T>What this app can check for itself. It cannot check PRAL registration or tokens -- see the D6 checklist for those.</T>
          </p>
          <ul className="mt-3 space-y-1.5 text-[15px]">
            <li className={readiness.itemsNotReady === 0 ? "text-cell-deep" : "text-terminal-deep"}>
              <T>{readiness.itemsNotReady === 0
                ? "All taxable items have an HS code and GST rate."
                : `${readiness.itemsNotReady} taxable item(s) still missing an HS code or GST rate.`}</T>
            </li>
            <li className={readiness.listsLoaded ? "text-cell-deep" : "text-terminal-deep"}>
              <T>{readiness.listsLoaded ? "The provinces list is loaded." : "The provinces list has not been loaded yet."}</T>
            </li>
            <li className={readiness.senderSeenRecently ? "text-cell-deep" : "text-terminal-deep"}>
              <T>{readiness.senderSeenRecently ? "The shop PC sender has been seen recently." : "The shop PC sender has not been seen recently."}</T>
            </li>
            <li className={readiness.failedCount === 0 && readiness.unknownCount === 0 ? "text-cell-deep" : "text-terminal-deep"}>
              <T>{readiness.failedCount === 0 && readiness.unknownCount === 0
                ? "No failed or unknown bills waiting."
                : `${readiness.failedCount} failed, ${readiness.unknownCount} unknown bill(s) waiting.`}</T>
            </li>
          </ul>
          {readiness.environment === "sandbox" && (
            <p className="mt-3 text-sm text-lead">
              <T>{isReadyForGoLive(readiness)
                ? "These checks all pass. Finish the D6/D8 human steps (real PRAL tokens, IP approval, a first watched day) before switching to Production."
                : "Fix the items above before switching to Production."}</T>
            </p>
          )}
        </section>
      )}

      <FbrListsClient
        kinds={FBR_KINDS as { kind: FbrKind; label: string; hint: string }[]}
        loaded={loaded}
        settings={{
          businessName: (profile.data?.business_name as string) ?? "",
          ntn: (profile.data?.ntn as string | null) ?? null,
          province: (profile.data?.province as string | null) ?? null,
          enabled: !!profile.data?.fbr_enabled,
          environment: (profile.data?.fbr_environment as string) ?? "sandbox",
          pricesIncludeTax: !!profile.data?.prices_include_tax,
        }}
        senderLastSeen={(heartbeat.data?.last_seen as string | null) ?? null}
      />
    </div>
  );
}
