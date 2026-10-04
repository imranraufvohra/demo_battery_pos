import Link from "next/link";
import Icon from "@/components/Icons";

import { T } from "@/components/T";
export default function PurchaseNotFound() {
  return (
    <div className="card anim-rise mx-auto max-w-md px-6 py-14 text-center">
      <span className="mx-auto inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-lead/10 text-lead">
        <Icon name="truck" className="h-8 w-8" />
      </span>
      <h1 className="mt-4 font-display text-3xl font-bold"><T>Purchase bill not found</T></h1>
      <p className="mt-2 text-lead"><T>This bill may have been removed, or the link is wrong.</T></p>
      <Link href="/purchases" className="btn btn-primary mt-6">
        <T>Back to purchases</T>
      </Link>
    </div>
  );
}
