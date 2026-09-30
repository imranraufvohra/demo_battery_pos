import { notFound } from "next/navigation";
import { MODULES } from "@/lib/modules";
import AppShell from "@/components/AppShell";

export default function FbrLayout({ children }: { children: React.ReactNode }) {
  return <AppShell>{children}</AppShell>;
}
