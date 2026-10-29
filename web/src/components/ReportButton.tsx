"use client";

import { useState } from "react";

const REASONS: [string, string][] = [
  ["inappropriate", "不適切だと思う"],
  ["harassment", "嫌がらせだと思う"],
  ["spam", "迷惑な内容だと思う"],
  ["other", "その他"],
];

/** 匿名の通報。定型の理由だけを送る（自由記述・画像はなし）。受付はサーバー成功後に表示する。 */
export function ReportButton({ token }: { token: string }) {
  const [reason, setReason] = useState("inappropriate");
  const [state, setState] = useState<"idle" | "sending" | "done" | "failed">("idle");

  async function send() {
    setState("sending");
    try {
      const response = await fetch("/api/public/reports", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, reason }),
      });
      setState(response.status === 201 ? "done" : "failed");
    } catch {
      setState("failed");
    }
  }

  return (
    <details className="report">
      <summary className="report">この共有を通報する</summary>
      {state === "done" ? (
        <p className="muted">通報を受け付けました。</p>
      ) : (
        <>
          {REASONS.map(([value, label]) => (
            <label key={value}>
              <input type="radio" name="reason" value={value} checked={reason === value} onChange={() => setReason(value)} /> {label}
            </label>
          ))}
          <button type="button" onClick={send} disabled={state === "sending"}>送る</button>
          {state === "failed" && <p className="muted">送れませんでした。時間をおいて、もう一度お試しください。</p>}
        </>
      )}
    </details>
  );
}
