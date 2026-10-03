import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ROLE_LABEL } from "@/lib/roles";
import { loadRoleInfo } from "@/lib/rolesServer";
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
  // Check the login token locally and load the role at the same time (was: two steps one after the other).
  const [{ data: claimsData }, info] = await Promise.all([supabase.auth.getClaims(), loadRoleInfo()]);
  const user = claimsData?.claims;

  if (!user) redirect(process.env.NEXT_PUBLIC_DEMO_MODE === "true" ? "/demo-start" : "/login");
  const email = (user.email as string | undefined) ?? "Signed in";

  if (info.status === "no_role" || info.status === "inactive") {
    return <NoAccess email={email} turnedOff={info.status === "inactive"} />;
  }

  const displayName = info.fullName || email;
  const roleLabel = info.role ? ROLE_LABEL[info.role] : "";

  return (
    <RoleProvider info={info}>
      <div className="min-h-dvh">
        <DemoBanner />
        <Sidebar email={email} name={displayName} roleLabel={roleLabel} />
        <div className="lg:pl-64">
          <TopBar email={displayName} />
          <main className="mx-auto w-full max-w-7xl px-4 pb-28 pt-5 lg:px-8 lg:pb-14 lg:pt-8">{children}</main>
        </div>
        <NavLinks variant="bottom" />
        <CommandHost />
      </div>
    </RoleProvider>
  );
}
