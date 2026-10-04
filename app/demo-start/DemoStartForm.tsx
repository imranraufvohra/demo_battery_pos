"use client";

import { useEffect, useState, type FormEvent, type ReactNode } from "react";
import Spinner from "@/components/Spinner";

import { T } from "@/components/T";
/**
 * Wraps the demo login form. The form still posts natively to /api/demo-login (the server sets the
 * session cookie and answers with a 303 redirect), so we do not cancel the submit. We only flip a
 * pending flag so the page does not look frozen while the server works.
 *
 * Why the pending state is never reset on success: a successful login navigates away and this page
 * is thrown away. A failed login redirects back to /demo-start?error=1, which loads a fresh page with
 * pending = false and the server-rendered error message. The one exception is the browser back/forward
 * cache, which can restore this page frozen in the pending state, so we reset on `pageshow`.
 */
export default function DemoStartForm({ children, footer }: { children: ReactNode; footer?: ReactNode }) {
  const [pending, setPending] = useState(false);

  useEffect(() => {
    const onPageShow = (e: PageTransitionEvent) => {
      if (e.persisted) setPending(false);
    };
    window.addEventListener("pageshow", onPageShow);
    return () => window.removeEventListener("pageshow", onPageShow);
  }, []);

  function onSubmit(e: FormEvent<HTMLFormElement>) {
    if (pending) {
      e.preventDefault(); // double click / Enter key: ignore, the first submit is already running
      return;
    }
    setPending(true); // let the native POST continue
  }

  return (
    <>
      <form
        action="/api/demo-login"
        method="post"
        onSubmit={onSubmit}
        aria-busy={pending}
        className="w-full max-w-sm space-y-5 text-center"
      >
        {children}

        <button
          type="submit"
          disabled={pending}
          aria-busy={pending}
          className={`flex min-h-12 w-full items-center justify-center gap-2.5 rounded-xl px-4 py-3 font-semibold text-black transition duration-150 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white active:scale-95 active:bg-amber-500 disabled:cursor-wait ${
            pending ? "scale-95 bg-amber-500" : "bg-amber-400 hover:bg-amber-300"
          }`}
        >
          {pending ? (
            <>
              <Spinner className="h-5 w-5" />
              <span><T>Starting demo...</T></span>
            </>
          ) : (
            <span><T>Log in to demo</T></span>
          )}
        </button>

        {/* Screen readers: announce the state change, since a disabled button loses focus. */}
        <span role="status" aria-live="polite" className="sr-only">
          <T>{pending ? "Starting demo, please wait" : ""}</T>
        </span>

        {footer}
      </form>

      {pending && (
        <div
          aria-hidden="true"
          className="anim-fade fixed inset-0 z-50 flex flex-col items-center justify-center gap-4 bg-[#1c2b33]/90 text-white backdrop-blur-sm"
        >
          <Spinner className="h-12 w-12 text-amber-400" />
          <p className="font-display text-xl font-semibold tracking-wide"><T>Opening your demo...</T></p>
        </div>
      )}
    </>
  );
}
