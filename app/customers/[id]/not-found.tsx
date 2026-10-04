import Link from "next/link";
import Icon from "@/components/Icons";

import { T } from "@/components/T";
export default function CustomerNotFound() {
  return (
    <div className="card anim-rise mx-auto max-w-md px-6 py-14 text-center">
      <span className="mx-auto inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-lead/10 text-lead">
        <Icon name="users" className="h-8 w-8" />
      </span>
      <h1 className="mt-4 font-display text-3xl font-bold"><T>Customer not found</T></h1>
      <p className="mt-2 text-lead"><T>This customer may have been deleted, or the link is wrong.</T></p>
      <Link href="/customers" className="btn btn-primary mt-6">
        <T>Back to customers</T>
      </Link>
    </div>
  );
}
