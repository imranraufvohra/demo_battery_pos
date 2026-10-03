import { ROUTE_MODULE } from "@/lib/modules";
import type { TKey } from "@/lib/i18n/en";
import type { IconName } from "./Icons";

export type NavItem = {
  href: string;
  /** Translation key (see lib/i18n/en.ts). Resolve with t(item.labelKey). */
  labelKey: TKey;
  icon: IconName;
  /** Home must match "/" exactly, otherwise it would look active on every page. */
  exact?: boolean;
  /** Shown in the desktop sidebar only. On phones it lives under More (the bottom bar holds 5 tabs at most). */
  desktopOnly?: boolean;
};

/*
  ADD NEW SECTIONS HERE. Only list screens that exist (no tabs that lead nowhere).
  Phone: the bottom bar is now a fixed layout (Home, Inventory, "+", Sales, More) per
  decision D7 -- see NavLinks.tsx. `desktopOnly` here just controls the SIDEBAR-vs-bottom-bar
  split; it no longer maps 1:1 onto "which 4 icons appear", since only Home/Inventory/Sales
  keep their own bottom-bar icon. Everything else (Customers included, moved off the bar by
  D7) is one tap away under More -- see app/more/page.tsx.
  Desktop: every item below appears in the sidebar, in this order, regardless of desktopOnly.
*/
const ALL_NAV_ITEMS: NavItem[] = [
  { href: "/", labelKey: "nav.home", icon: "home", exact: true },
  { href: "/inventory", labelKey: "nav.inventory", icon: "battery" },
  { href: "/customers", labelKey: "nav.customers", icon: "users", desktopOnly: true },
  { href: "/sales", labelKey: "nav.sales", icon: "receipt" },
  { href: "/udhaar", labelKey: "nav.credit", icon: "alert", desktopOnly: true },
  { href: "/suppliers", labelKey: "nav.suppliers", icon: "truck", desktopOnly: true },
  { href: "/purchases", labelKey: "nav.purchases", icon: "cart", desktopOnly: true },
  { href: "/payments", labelKey: "nav.payments", icon: "banknote", desktopOnly: true },
  { href: "/expenses", labelKey: "nav.expenses", icon: "minus", desktopOnly: true },
  { href: "/reports", labelKey: "nav.reports", icon: "chart", desktopOnly: true },
  { href: "/battery-services", labelKey: "nav.batteryServices", icon: "plug", desktopOnly: true },
  { href: "/scrap", labelKey: "nav.scrap", icon: "box", desktopOnly: true },
  { href: "/assistant", labelKey: "nav.assistant", icon: "sparkle", desktopOnly: true },
  // Owner only (see lib/roles.ts). On a phone they are under More.
  { href: "/activity", labelKey: "nav.activity", icon: "shield", desktopOnly: true },
  { href: "/team", labelKey: "nav.team", icon: "idcard", desktopOnly: true },
  { href: "/fbr", labelKey: "nav.fbr", icon: "shield", desktopOnly: true },
];

export const NAV_ITEMS: NavItem[] = ALL_NAV_ITEMS.filter((i) => ROUTE_MODULE[i.href] !== false);

export const MORE_ITEM: NavItem = { href: "/more", labelKey: "nav.more", icon: "more" };
