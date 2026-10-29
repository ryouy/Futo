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
        <p>「ふと」アプリが入っている iPhone では、このリンクを開くと、アプリで招待が開きます。</p>
        <p className="muted">
          アプリがまだ入っていない場合は、テスト版の導入のあとで、このリンクをもう一度開いてください（インストール後に、自動で復元されるとは限りません）。
          リンクが開けないときは、招待した人から教わったコードを、アプリの「コードを入力」に入力してください。
        </p>
      </div>
      <p className="muted" style={{ textAlign: "center" }}>承認されるまで、フレンドにはなりません。心当たりがなければ、開かなくて大丈夫です。</p>
    </>
  );
}
