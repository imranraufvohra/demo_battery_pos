import Link from "next/link";

import { T } from "@/components/T";
export default function NotFound() {
  return (
    <div className="card mx-auto mt-8 max-w-md p-8 text-center">
      <h1 className="font-display text-3xl font-bold"><T>Bill not found</T></h1>
      <p className="mt-2 text-lead"><T>This bill does not exist, or the link is wrong. Open Sales to find it.</T></p>
      <Link href="/sales" className="btn btn-primary mt-5">
        <T>Go to Sales</T>
      </Link>
    </div>
  );
}
