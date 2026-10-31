import { Timestamp } from "firebase-admin/firestore";
import { now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { billingConfig, stripeRequest, type BillingConfig } from "./stripe";
import { userRef } from "./users";

/** Web（Stripe）で加入できるプラン。App Store 側のプランと同じ名前・同じ権利。 */
export type WebPlan = "adFree" | "support";

/** 広告なし（100円 / 月）とふとを応援（500円 / 月）。表示用の金額。実際の請求額は、Stripe の価格で決まる。 */
export const WEB_PRICES: Record<WebPlan, number> = { adFree: 100, support: 500 };

export interface WebPlanRecord {
  plan: WebPlan;
  status: string;
  currentPeriodEnd: string | null;
  customerId: string;
  subscriptionId: string;
}

/** 権利が有効な状態（支払い失敗の再試行中などは、含めない）。 */
export const isActiveStatus = (status: string) => status === "active" || status === "trialing";

export function planForPrice(priceId: string | undefined, config: Pick<BillingConfig, "priceAdFree" | "priceSupport">): WebPlan | null {
  if (!priceId) return null;
  if (priceId === config.priceSupport) return "support";
  if (priceId === config.priceAdFree) return "adFree";
  return null;
}

interface StripeSubscription {
  id: string;
  status: string;
  customer: string | { id: string };
  current_period_end?: number;
  items?: { data?: { price?: { id?: string }; current_period_end?: number }[] };
  metadata?: Record<string, string>;
}

/** Stripe の契約から、保存する形を作る。知らない価格の契約は、無視する（null）。 */
export function recordFromSubscription(sub: StripeSubscription, config: Pick<BillingConfig, "priceAdFree" | "priceSupport">): WebPlanRecord | null {
  const item = sub.items?.data?.[0];
  const plan = planForPrice(item?.price?.id, config);
  if (!plan) return null;
  const end = item?.current_period_end ?? sub.current_period_end;
  return {
    plan,
    status: sub.status,
    currentPeriodEnd: end ? new Date(end * 1000).toISOString() : null,
    customerId: typeof sub.customer === "string" ? sub.customer : sub.customer.id,
    subscriptionId: sub.id,
  };
}

/** アカウントに、Web の加入状況を保存する。アカウントが無い・削除中なら、何もしない。 */
export async function saveWebPlan(uid: string, record: WebPlanRecord): Promise<boolean> {
  const ref = userRef(uid);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()?.status !== "active") return false;
    tx.update(ref, { webPlan: record, updatedAt: Timestamp.fromDate(now()) });
    return true;
  });
}

/** いま有効な Web のプラン（なければ null）。アプリはこれを見て、広告を出さない。 */
export function activeWebPlan(userData: { webPlan?: Partial<WebPlanRecord> } | undefined): WebPlan | null {
  const record = userData?.webPlan;
  if (!record?.plan || !record.status || !isActiveStatus(record.status)) return null;
  return record.plan;
}

/** チェックアウトを始める。すでに有効な Web の契約があるなら、変更は、契約の管理（ポータル）で行う。 */
export async function createCheckout(config: BillingConfig, uid: string, plan: WebPlan, returnBase: string): Promise<string> {
  const snap = await userRef(uid).get();
  const data = snap.data();
  if (!snap.exists || data?.status !== "active") throw new ApiError(403, "profile_required");
  if (activeWebPlan(data)) throw new ApiError(409, "already_subscribed");
  const price = plan === "support" ? config.priceSupport : config.priceAdFree;
  const customerId = (data?.webPlan as Partial<WebPlanRecord> | undefined)?.customerId;
  const session = await stripeRequest<{ url?: string }>(config, "POST", "/checkout/sessions", {
    mode: "subscription",
    line_items: [{ price, quantity: 1 }],
    client_reference_id: uid,
    ...(customerId ? { customer: customerId } : {}),
    subscription_data: { metadata: { uid } },
    success_url: `${returnBase}/support?status=success`,
    cancel_url: `${returnBase}/support`,
    locale: "ja",
  });
  if (!session.url) throw new ApiError(502, "billing_unavailable");
  return session.url;
}

/** 契約の管理（プラン変更・解約・支払い方法）。Stripe のポータルへ。 */
export async function createPortal(config: BillingConfig, uid: string, returnBase: string): Promise<string> {
  const data = (await userRef(uid).get()).data();
  const customerId = (data?.webPlan as Partial<WebPlanRecord> | undefined)?.customerId;
  if (!customerId) throw new ApiError(404, "not_found");
  const session = await stripeRequest<{ url?: string }>(config, "POST", "/billing_portal/sessions", { customer: customerId, return_url: `${returnBase}/support` });
  if (!session.url) throw new ApiError(502, "billing_unavailable");
  return session.url;
}

/** アカウント削除のとき、Web の契約を解約する（請求が続かないように）。設定が無ければ、何もできない。 */
export async function cancelWebSubscription(uid: string): Promise<void> {
  const data = (await userRef(uid).get()).data();
  const subscriptionId = (data?.webPlan as Partial<WebPlanRecord> | undefined)?.subscriptionId;
  if (!subscriptionId) return;
  const config = billingConfig();
  if (!config) return;
  try {
    await stripeRequest(config, "DELETE", `/subscriptions/${encodeURIComponent(subscriptionId)}`);
  } catch (error) {
    // もう無い契約は、解約済みと同じ
    if (!(error instanceof ApiError && error.status === 404)) throw error;
  }
}
