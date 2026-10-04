import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { loadPurchaseDocument } from "@/lib/purchaseDoc";
import PurchaseDetail from "./PurchaseDetail";

import { getT } from "@/lib/i18n/server";
export async function generateMetadata(): Promise<Metadata> {
  return { title: (await getT())("Purchase bill") };
}

export default async function PurchasePage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const doc = await loadPurchaseDocument(id);
  if (!doc) notFound();

  return <PurchaseDetail {...doc} />;
}
