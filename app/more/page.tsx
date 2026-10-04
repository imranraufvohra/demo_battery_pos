import type { Metadata } from "next";
import Link from "next/link";
import Avatar from "@/components/Avatar";
import Icon, { type IconName } from "@/components/Icons";
import InstallAppButton from "@/components/InstallAppButton";
import PageHeader from "@/components/PageHeader";
import SignOutButton from "@/components/SignOutButton";
import { createClient } from "@/lib/supabase/server";
import { canOpen } from "@/lib/roles";
import LangSwitcher from "@/components/LangSwitcher";
import { getT } from "@/lib/i18n/server";
import type { TKey } from "@/lib/i18n/en";
import { loadRoleInfo } from "@/lib/rolesServer";

import { T } from "@/components/T";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("nav.more") };
}

// Only shortcuts to screens that exist. Import/Export and Settings will be added with their phases.
// Customers, Suppliers, Purchases, Payments and Expenses live here rather than on the phone bottom
// bar: decision D7 gave the bottom bar's center slot to the "+" quick-actions button instead, which
// only fit by moving Customers off its own icon (still one tap away, here) -- Suppliers/Purchases
// (F1), Payments (F2) and Expenses (F3) are new since then and were never on the bar to begin with.
const SHORTCUTS: { href: string; tkey: TKey; icon: IconName; tone: string }[] = [
  { href: "/assistant", tkey: "more.assistant", icon: "sparkle", tone: "bg-sun/25 text-amber-800" },
  { href: "/sales/new", tkey: "more.newBill", icon: "receipt", tone: "bg-sun/25 text-amber-800" },
  { href: "/udhaar", tkey: "more.credit", icon: "banknote", tone: "bg-terminal/10 text-terminal" },
  { href: "/purchases/new", tkey: "more.receiveStock", icon: "truck", tone: "bg-focus/10 text-focus" },
  { href: "/payments/new", tkey: "more.makePayment", icon: "banknote", tone: "bg-cell/10 text-cell" },
  { href: "/suppliers", tkey: "more.suppliers", icon: "truck", tone: "bg-lead/10 text-casing" },
  { href: "/purchases", tkey: "more.purchaseBills", icon: "cart", tone: "bg-cell/10 text-cell" },
  { href: "/payments", tkey: "more.payments", icon: "banknote", tone: "bg-lead/10 text-casing" },
  { href: "/expenses?add=1", tkey: "more.addExpense", icon: "minus", tone: "bg-terminal/10 text-terminal-deep" },
  { href: "/expenses", tkey: "more.expenses", icon: "minus", tone: "bg-lead/10 text-casing" },
  { href: "/customers", tkey: "more.customers", icon: "users", tone: "bg-focus/10 text-focus" },
  { href: "/reports", tkey: "more.reports", icon: "chart", tone: "bg-focus/10 text-focus" },
  { href: "/inventory?add=1", tkey: "more.addItem", icon: "plus", tone: "bg-cell/10 text-cell" },
  { href: "/customers?add=1", tkey: "more.addCustomer", icon: "userplus", tone: "bg-focus/10 text-focus" },
  { href: "/inventory?filter=low", tkey: "more.lowStock", icon: "alert", tone: "bg-terminal/10 text-terminal" },
  { href: "/battery-services", tkey: "more.batteryServices", icon: "plug", tone: "bg-focus/10 text-focus" },
  { href: "/scrap", tkey: "more.scrap", icon: "box", tone: "bg-lead/10 text-casing" },
  { href: "/activity", tkey: "more.activity", icon: "shield", tone: "bg-sun/25 text-amber-800" },
  { href: "/team", tkey: "more.team", icon: "idcard", tone: "bg-focus/10 text-focus" },
  { href: "/fbr", tkey: "more.fbr", icon: "shield", tone: "bg-sun/25 text-amber-800" },
];

export default async function MorePage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  const t = await getT();
  const email = user?.email ?? t("shell.signedIn");
  const info = await loadRoleInfo();
  const name = info.fullName || email;
  const shortcuts = SHORTCUTS.filter((s) => canOpen(info, s.href.split("?")[0]));

  return (
    <div className="mx-auto max-w-2xl">
      <PageHeader title={t("nav.more")} />

      <section className="card anim-rise mt-6 flex items-center gap-4 p-5" style={{ "--i": 1 } as React.CSSProperties}>
        <Avatar name={name} size="lg" />
        <div className="min-w-0">
          <p className="text-sm text-lead">{t("shell.signedInAs")}</p>
          <p className="truncate font-semibold" title={email}>
            {name}
          </p>
          <p className="truncate text-sm text-lead">
            <T>{info.role ? t(`role.${info.role}`) + " · " : ""}</T>
            {email}
          </p>
        </div>
      </section>

      <ul className="anim-rise mt-4 space-y-2.5" style={{ "--i": 2 } as React.CSSProperties}>
        {shortcuts.map((s) => (
          <li key={s.href}>
            <Link href={s.href} className="card card-hover flex items-center gap-3.5 p-4">
              <span className={`inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl ${s.tone}`}>
                <Icon name={s.icon} className="h-5 w-5" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block font-semibold">{t(s.tkey)}</span>
                <span className="block text-sm text-lead">{t(`${s.tkey}.hint` as TKey)}</span>
              </span>
              <Icon name="chevron" className="h-4 w-4 text-lead/60" />
            </Link>
          </li>
        ))}
      </ul>

      <div className="anim-rise mt-6 space-y-2.5" style={{ "--i": 3 } as React.CSSProperties}>
        <LangSwitcher variant="row" />
        <InstallAppButton />
        <SignOutButton />
      </div>
    </div>
  );
}
