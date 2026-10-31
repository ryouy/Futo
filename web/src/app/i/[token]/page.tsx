import { headers } from "next/headers";
import { isConfigured } from "@/lib/firebase";
import { ApiError } from "@/lib/http";
import { getPublicInvitation } from "@/lib/invitations";
import { clientKeyFromHeaders } from "@/lib/rateLimit";

export const dynamic = "force-dynamic";
export const revalidate = 0;

/** 招待ページ。GETでは、申請も使用済みへの変更もしない（リンクのプレビューやスキャンで消費されない）。 */
export default async function InvitePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  let info: { inviterName: string; expiresAt: string; code: string | null } | null = null;
  if (isConfigured()) {
    try {
      info = await getPublicInvitation(token, clientKeyFromHeaders(await headers()));
    } catch (error) {
      if (!(error instanceof ApiError)) throw error;
    }
  }
  if (!info) {
    return (
      <div className="card unavailable">
        <h2>この招待は利用できません</h2>
        <p className="muted">期限が切れているか、すでに使われています　招待した人に、新しい招待をお願いしてください</p>
      </div>
    );
  }
  const expires = new Intl.DateTimeFormat("sv-SE", { dateStyle: "short", timeStyle: "short", timeZone: "Asia/Tokyo" }).format(new Date(info.expiresAt));
  return (
    <div className="card">
      <p className="who">{info.inviterName}さんからの招待</p>
      <p className="muted">期限：{expires}（日本時間）　承認されるまで、フレンドにはなりません</p>
      {info.code && (
        <p className="codebox">
          招待コード <strong>{info.code.replace(/(.{4})(?=.)/g, "$1-")}</strong>
        </p>
      )}
      <div className="btns">
        <a className="btn" href={`futo://invite/${encodeURIComponent(token)}`}>ふとアプリで開く</a>
        <a className="btn ghost" href="/">ふとの紹介</a>
      </div>
      <p className="muted">アプリがない方は「ふとの紹介」へ　開けないときは、教わった招待コードをアプリに入力してください</p>
    </div>
  );
}
