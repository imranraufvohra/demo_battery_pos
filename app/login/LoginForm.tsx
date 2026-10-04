"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { getBrowserClient } from "@/lib/supabase/lazy";
import { useT } from "@/lib/i18n/client";

import { T } from "@/components/T";
export default function LoginForm() {
  const router = useRouter();
  const t = useT();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setError(null);

    try {
      const supabase = await getBrowserClient();
      const { error } = await supabase.auth.signInWithPassword({
        email: email.trim(),
        password,
      });

      if (error) {
        setError(
          error.message.toLowerCase().includes("invalid login")
            ? t("login.badCredentials")
            : error.message
        );
        setBusy(false);
        return;
      }

      // replace() already loads the home page fresh; the extra refresh() fetched it a second time.
      router.replace("/");
    } catch {
      setError(t("login.offline"));
      setBusy(false);
    }
  }

  return (
    <form onSubmit={onSubmit} className="mt-8 space-y-5" noValidate>
      <div>
        <label htmlFor="email" className="mb-1.5 block text-sm font-medium">
          {t("common.email")}
        </label>
        <input
          id="email"
          type="email"
          autoComplete="email"
          dir="ltr"
          autoFocus
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="input"
        />
      </div>

      <div>
        <label htmlFor="password" className="mb-1.5 block text-sm font-medium">
          {t("common.password")}
        </label>
        <input
          id="password"
          type="password"
          autoComplete="current-password"
          required
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="input"
        />
      </div>

      {error && (
        <p role="alert" className="rounded-md bg-terminal/10 px-3 py-2 text-sm text-terminal-deep">
          <T>{error}</T>
        </p>
      )}

      <button type="submit" disabled={busy || !email || !password} className="btn btn-primary w-full">
        <T>{busy ? t("login.submitting") : t("login.submit")}</T>
      </button>
    </form>
  );
}
