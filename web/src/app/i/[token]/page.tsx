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
  let info: { inviterName: string; expiresAt: string } | null = null;
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
        <p className="muted">期限が切れているか、すでに使われています。招待した人に、新しい招待をお願いしてください。</p>
      </div>
    );
  }
  const expires = new Intl.DateTimeFormat("ja-JP", { dateStyle: "medium", timeStyle: "short", timeZone: "Asia/Tokyo" }).format(new Date(info.expiresAt));
  return (
    <>
      <div className="card">
        <p className="who">{info.inviterName}さんからの招待</p>
        <p className="muted">期限：{expires}（日本時間）</p>
      </div>
      <div className="card">
        <h2>アプリで開く</h2>
        <p>「ふと」アプリが入っている iPhone では、下のボタンでアプリが開き、招待の内容が表示されます。</p>
        <p>
          <a className="btn" href={`futo://invite/${encodeURIComponent(token)}`}>ふとアプリで開く</a>
        </p>
        <p className="muted">LINE などのアプリ内ブラウザでは、このボタンを使ってください。うまく開かないときは、招待した人から教わったコードを、アプリの「招待コードを入力」に入力できます。</p>
      </div>
      <div className="card">
        <h2>アプリがまだの方へ</h2>
        <p className="muted">「ふと」は、スマホを開く前にひと呼吸おくための iPhone アプリです。どんなアプリか、紹介ページで見られます。</p>
        <p>
          <a className="btn ghost" href="/">ふとの紹介を見る</a>
        </p>
      </div>
      <p className="muted" style={{ textAlign: "center" }}>承認されるまで、フレンドにはなりません。心当たりがなければ、開かなくて大丈夫です。</p>
    </>
  );
}
