import { recordFromSubscription, saveWebPlan } from "@/lib/billing";
import { now } from "@/lib/clock";
import { ApiError, handle, json } from "@/lib/routeHelpers";
import { billingConfig, stripeRequest, verifyStripeSignature } from "@/lib/stripe";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

interface StripeEvent {
  type: string;
  data: { object: Record<string, unknown> };
}

/**
 * Stripe からの通知。署名を確かめてから、契約の状態をアカウントに反映する。
 * 同じ通知が何度届いても、結果は同じ（状態を、そのまま上書きするだけ）。
 */
export const POST = (req: Request) =>
  handle(async () => {
    const config = billingConfig();
    if (!config) throw new ApiError(503, "billing_not_configured");
    const raw = await req.text();
    if (!verifyStripeSignature(raw, req.headers.get("stripe-signature"), config.webhookSecret, Math.floor(now().getTime() / 1000))) {
      throw new ApiError(400, "invalid_signature");
    }
    const event = JSON.parse(raw) as StripeEvent;
    const object = event.data.object;
    let subscription: Record<string, unknown> | null = null;
    if (event.type.startsWith("customer.subscription.")) {
      subscription = object;
    } else if (event.type === "checkout.session.completed" && typeof object.subscription === "string") {
      // 決済が終わった直後。契約の中身を、Stripe から取り直す
      subscription = await stripeRequest<Record<string, unknown>>(config, "GET", `/subscriptions/${encodeURIComponent(object.subscription)}`);
    }
    if (subscription) {
      const metadata = subscription.metadata as Record<string, string> | undefined;
      const uid = metadata?.uid;
      const record = recordFromSubscription(subscription as never, config);
      if (uid && record) await saveWebPlan(uid, record);
    }
    return json(200, { received: true });
  });
