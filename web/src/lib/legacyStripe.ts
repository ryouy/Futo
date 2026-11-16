import { ApiError } from "./http";
import { userRef } from "./users";

/**
 * 【終了した Web 課金の後始末だけ】
 * Futo の Web 課金（Stripe の月額）は廃止した。購入・契約の管理・権利の反映は、もう無い。
 * ここに残すのは、過去に Web で契約した人がいた場合に、アカウントを削除しても請求が続かないように、
 * その契約を解約することだけ。契約者がいないと Stripe で確認できたら、このファイルごと削除してよい。
 * 秘密鍵は、環境変数 STRIPE_SECRET_KEY（無ければ何もしない）。
 */
export async function cancelLegacyWebSubscription(uid: string): Promise<void> {
  const data = (await userRef(uid).get()).data();
  const subscriptionId = (data?.webPlan as { subscriptionId?: string } | undefined)?.subscriptionId;
  if (!subscriptionId) return;
  const secretKey = process.env.STRIPE_SECRET_KEY;
  if (!secretKey) return;
  const response = await fetch(`https://api.stripe.com/v1/subscriptions/${encodeURIComponent(subscriptionId)}`, {
    method: "DELETE",
    headers: { authorization: `Bearer ${secretKey}` },
  });
  // もう無い契約は、解約済みと同じ
  if (!response.ok && response.status !== 404) throw new ApiError(502, "billing_unavailable");
}
