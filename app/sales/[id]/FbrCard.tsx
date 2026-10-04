"use client";

import { useState } from "react";
import { useRoleInfo } from "@/components/RoleProvider";
import { effectiveRole } from "@/lib/roles";
import { fbrMeaning, type FbrInfo } from "@/lib/fbrStatus";
import FbrBadge from "../FbrBadge";

import { T } from "@/components/T";
const when = new Intl.DateTimeFormat("en-GB", {
  day: "numeric",
  month: "short",
  hour: "numeric",
  minute: "2-digit",
  hour12: true,
  timeZone: (process.env.NEXT_PUBLIC_TIMEZONE ?? "UTC"),
});

function fmt(iso: string | null): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : when.format(d);
}

/** The "FBR" box on one bill: status, FBR invoice number, and (for the Owner and Accountant) FBR's error text. */
export default function FbrCard({ info, invoiceNumber, cancelled }: { info: FbrInfo; invoiceNumber: string; cancelled: boolean }) {
  const role = effectiveRole(useRoleInfo());
  const seesDetail = role === "owner" || role === "accountant";
  const isOwner = role === "owner";
  const [copied, setCopied] = useState(false);

  const showProblem = seesDetail && (info.status === "failed" || info.status === "unknown") && (info.errorMessage || info.errorCode);
  const nextTry = info.status === "pending" && info.attempts > 0 ? fmt(info.nextRetryAt) : null;
  const sentAt = info.status === "sent" ? fmt(info.submittedAt) : null;

  async function copyNumber() {
    if (!info.number) return;
    try {
      await navigator.clipboard.writeText(info.number);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      /* clipboard not available: the number is still on screen */
    }
  }

  return (
    <section className="card anim-rise p-5" style={{ "--i": 2 } as React.CSSProperties}>
      <div className="flex items-center justify-between gap-3">
        <h2 className="font-display text-2xl font-semibold"><T>FBR</T></h2>
        <FbrBadge info={info} />
      </div>

      <p className="mt-2 text-[15px] text-lead"><T>{fbrMeaning(info, cancelled)}</T></p>

      {info.number && (
        <div className="mt-3 rounded-xl bg-plate/70 px-3 py-2.5">
          <p className="text-sm text-lead"><T>FBR invoice number</T></p>
          <div className="flex items-center justify-between gap-3">
            <p className="break-all font-semibold tabular-nums">{info.number}</p>
            <button type="button" onClick={copyNumber} className="shrink-0 text-sm font-semibold text-focus hover:underline">
              <T>{copied ? "Copied" : "Copy"}</T>
            </button>
          </div>
        </div>
      )}

      <dl className="mt-3 space-y-1 text-sm text-lead">
        {sentAt && <div><T p={{ sentAt: sentAt }}>{"Sent {sentAt}"}</T></div>}
        {nextTry && <div><T p={{ nextTry: nextTry }}>{"Next try: {nextTry}"}</T></div>}
        {seesDetail && info.attempts > 0 && info.status !== "sent" && (
          <div>
            <T p={{ n: info.attempts }}>{info.attempts === 1 ? "{n} try so far" : "{n} tries so far"}</T>
          </div>
        )}
      </dl>

      {showProblem && (
        <div role="alert" className="mt-3 rounded-xl bg-terminal/10 px-3 py-2.5 text-[15px] text-terminal-deep">
          <p className="font-semibold"><T>What FBR said</T></p>
          {info.errorCode && <p className="tabular-nums"><T p={{ errorCode: info.errorCode }}>{"Error code {errorCode}"}</T></p>}
          {info.errorMessage && <p className="mt-0.5 whitespace-pre-line break-words">{info.errorMessage}</p>}
        </div>
      )}

      {!seesDetail && (info.status === "failed" || info.status === "unknown") && !cancelled && (
        <p className="mt-3 rounded-xl bg-terminal/10 px-3 py-2.5 text-[15px] text-terminal-deep">
          <T>There is a problem with this bill at FBR. Please tell the Owner.</T>
        </p>
      )}

      {isOwner && (info.status === "failed" || info.status === "unknown") && !cancelled && (
        <div className="mt-3 rounded-xl bg-plate/70 px-3 py-2.5 text-[15px]">
          <p className="font-semibold"><T>To send it again</T></p>
          <p className="mt-0.5 text-lead">
            <T>{info.status === "unknown"
              ? "First look for this bill on the FBR portal. Only if it is not there, run this on the shop PC in C:\\fbr-sender:"
              : "Fix the cause first, then run this on the shop PC in C:\\fbr-sender:"}</T>
          </p>
          <code className="mt-1.5 block break-all rounded-lg bg-white px-2.5 py-2 text-sm text-casing">
            node src/cli.js retry {invoiceNumber}
            {info.status === "unknown" ? " --yes-i-checked-fbr" : ""}
          </code>
        </div>
      )}
    </section>
  );
}
