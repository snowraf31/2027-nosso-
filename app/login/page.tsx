"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/browser";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await createClient().auth.signInWithPassword({ email, password });
    setBusy(false);
    if (error) {
      setError("Email or password is incorrect.");
      return;
    }
    const next = new URLSearchParams(window.location.search).get("next");
    const safe = next && next.startsWith("/") && !next.startsWith("//") ? next : "/kitchen";
    router.replace(safe);
    router.refresh();
  }

  return (
    <main className="center">
      <form className="card" onSubmit={onSubmit}>
        <h1>Staff sign in</h1>
        <label className="field" htmlFor="email">
          Email
          <input id="email" type="email" autoComplete="email" required value={email} onChange={(e) => setEmail(e.target.value)} />
        </label>
        <label className="field" htmlFor="password">
          Password
          <input id="password" type="password" autoComplete="current-password" required value={password} onChange={(e) => setPassword(e.target.value)} />
        </label>
        {error && <div className="error" role="alert">{error}</div>}
        <button className="btn block" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
      </form>
    </main>
  );
}
