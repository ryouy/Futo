import { headers } from "next/headers";
import { Bi } from "@/components/Bi";
import { ShareView } from "@/components/ShareView";
import { ConfigError, isConfigured } from "@/lib/firebase";
import { ApiError } from "@/lib/http";
import { clientKeyFromHeaders } from "@/lib/rateLimit";
import { getPublicShare, type PublicShare } from "@/lib/shares";

// 毎回サーバーで描画し、期限・取消・所有者の状態を確認する（静的生成・ISR・CDNキャッシュに残さない）
export const dynamic = "force-dynamic";
export const revalidate = 0;

function Unavailable({ configured = true }: { configured?: boolean }) {
  return (
    <div className="card unavailable">
      <h2>{configured ? <Bi ja="この共有は利用できません" en="This share isn't available" /> : <Bi ja="現在、利用できません" en="Not available right now" />}</h2>
      <p className="muted"><Bi ja="リンクの期限が切れているか、取り消されています" en="The link has expired or was revoked" /></p>
    </div>
  );
}

export default async function SharePage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  if (!isConfigured()) return <Unavailable configured={false} />;
  let share: PublicShare;
  try {
    share = await getPublicShare(token, clientKeyFromHeaders(await headers()));
  } catch (error) {
    if (error instanceof ApiError || error instanceof ConfigError) return <Unavailable />;
    throw error;
  }
  return <ShareView share={share} />;
}
