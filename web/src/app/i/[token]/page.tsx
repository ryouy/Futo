import { headers } from "next/headers";
import { Bi } from "@/components/Bi";
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
        <h2><Bi ja="この招待は利用できません" en="This invitation isn't available" /></h2>
        <p className="muted"><Bi ja="期限が切れているか、すでに使われています　招待した人に、新しい招待をお願いしてください" en="It has expired or was already used, ask the person who invited you for a new one" /></p>
      </div>
    );
  }
  const expires = new Intl.DateTimeFormat("sv-SE", { dateStyle: "short", timeStyle: "short", timeZone: "Asia/Tokyo" }).format(new Date(info.expiresAt)).replaceAll("-", "/");
  return (
    <div className="card">
      <p className="who"><Bi ja={`${info.inviterName}さんからの招待`} en={`Invitation from ${info.inviterName}`} /></p>
      <p className="muted"><Bi ja={`期限：${expires}（日本時間）　承認されるまで、フレンドにはなりません`} en={`Expires ${expires} (JST), you become friends only after approval`} /></p>
      {info.code && (
        <p className="codebox">
          <Bi ja="招待コード" en="Invite code" /> <strong>{info.code.replace(/(.{4})(?=.)/g, "$1-")}</strong>
        </p>
      )}
      <div className="btns">
        <a className="btn" href={`futo://invite/${encodeURIComponent(token)}`}><Bi ja="ふとアプリで開く" en="Open in Futo" /></a>
        <a className="btn ghost" href="/"><Bi ja="ふとの紹介" en="About Futo" /></a>
      </div>
      <p className="muted"><Bi ja="アプリがない方は「ふとの紹介」へ　開けないときは、教わった招待コードをアプリに入力してください" en="No app yet? See About Futo, and if the link won't open, enter the invite code in the app" /></p>
    </div>
  );
}
