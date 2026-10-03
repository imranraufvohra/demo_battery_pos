import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { loadRoleInfo } from "@/lib/rolesServer";
import { getT } from "@/lib/i18n/server";
import DemoBanner from "./DemoBanner";
import CommandHost from "./CommandHost";
import NavLinks from "./NavLinks";
import NoAccess from "./NoAccess";
import { RoleProvider } from "./RoleProvider";
import Sidebar from "./Sidebar";
import TopBar from "./TopBar";

/**
 * The frame around every signed-in screen:
 * phone and tablet = top bar + bottom tab bar, desktop (1024px+) = dark sidebar + top bar.
 */
export default async function AppShell({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  // Fast check first (token verified locally); fall back to getUser() so this can never crash.
  const infoPromise = loadRoleInfo();
  let user: { email?: string } | null = null;
  try {
    const { data } = await supabase.auth.getClaims();
    user = (data?.claims as { email?: string } | undefined) ?? null;
  } catch {
    user = null;
  }
  if (!user) {
    const { data } = await supabase.auth.getUser();
    user = data.user;
  }

  if (!user) redirect(process.env.NEXT_PUBLIC_DEMO_MODE === "true" ? "/demo-start" : "/login");
  const email = user.email ?? "Signed in";

  const info = await infoPromise;
  if (info.status === "no_role" || info.status === "inactive") {
    return <NoAccess email={email} turnedOff={info.status === "inactive"} />;
  }

  const displayName = info.fullName || email;
  const t = await getT();
  const roleLabel = info.role ? t(`role.${info.role}`) : "";

  return (
    <RoleProvider info={info}>
      <div className="min-h-dvh">
        <DemoBanner />
        <Sidebar email={email} name={displayName} roleLabel={roleLabel} />
        <div className="lg:ps-64">
          <TopBar email={displayName} />
          <main className="mx-auto w-full max-w-7xl px-4 pb-28 pt-5 lg:px-8 lg:pb-14 lg:pt-8">{children}</main>
        </div>
        <NavLinks variant="bottom" />
        <CommandHost />
      </div>
    </RoleProvider>
  );
}
