"use client";

import { useState } from "react";
import { Bi } from "./Bi";

type Plan = "adFree" | "support";

async function post(path: string, body?: unknown): Promise<{ url?: string; error?: string }> {
  const response = await fetch(path, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body ?? {}) });
  const data = (await response.json().catch(() => ({}))) as { url?: string; error?: string };
  return response.ok ? data : { error: data.error ?? "failed" };
}

/** 加入・契約の管理・ログアウトのボタン。決済と管理は、Stripe の画面で行う。 */
export function SupportActions({ mode, plan }: { mode: "subscribe" | "manage" | "logout"; plan?: Plan }) {
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  async function go(path: string, body?: unknown) {
    setBusy(true);
    setFailed(false);
    const result = await post(path, body);
    if (result.url) {
      window.location.href = result.url;
      return;
    }
    setFailed(true);
    setBusy(false);
  }

  if (mode === "logout") {
    return (
      <button
        type="button"
        className="btn ghost"
        disabled={busy}
        onClick={async () => {
          setBusy(true);
          await post("/api/web/logout");
          window.location.href = "/support";
        }}
      >
        <Bi ja="ログアウト" en="Log out" />
      </button>
    );
  }
  return (
    <>
      <button type="button" className={mode === "subscribe" ? "btn" : "btn ghost"} disabled={busy} onClick={() => go(mode === "subscribe" ? "/api/billing/checkout" : "/api/billing/portal", mode === "subscribe" ? { plan } : undefined)}>
        {mode === "subscribe" ? <Bi ja="加入する" en="Subscribe" /> : <Bi ja="契約の管理" en="Manage subscription" />}
      </button>
      {failed && (
        <p className="muted">
          <Bi ja="うまくいきませんでした　もう一度お試しください" en="Something went wrong, please try again" />
        </p>
      )}
    </>
  );
}
