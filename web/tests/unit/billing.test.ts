import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { activeWebPlan, planForPrice, recordFromSubscription, WEB_PRICES } from "@/lib/billing";
import { billingConfig, encodeParams, verifyStripeSignature } from "@/lib/stripe";
import { cookieHeader, googleAuthUrl, parseCookie, webAuthConfig } from "@/lib/webSession";

const prices = { priceAdFree: "price_adfree", priceSupport: "price_support" };

describe("Web課金：設定", () => {
  const env = { STRIPE_SECRET_KEY: "sk", STRIPE_WEBHOOK_SECRET: "whsec", STRIPE_PRICE_ADFREE: "p1", STRIPE_PRICE_SUPPORT: "p2", LEGAL_SELLER_NAME: "n", LEGAL_ADDRESS: "a", LEGAL_CONTACT: "c" } as unknown as NodeJS.ProcessEnv;

  it("決済のキー・価格・特商法の表記が、すべてそろうときだけ有効", () => {
    expect(billingConfig(env)).not.toBeNull();
    for (const key of Object.keys(env)) {
      const partial = { ...env };
      delete partial[key];
      expect(billingConfig(partial), `${key} が無いときは無効`).toBeNull();
    }
  });

  it("価格は、広告なし100円・ふとを応援500円", () => {
    expect(WEB_PRICES).toEqual({ adFree: 100, support: 500 });
  });

  it("Googleログインの設定が足りなければ無効", () => {
    expect(webAuthConfig({ GOOGLE_WEB_CLIENT_ID: "a", GOOGLE_WEB_CLIENT_SECRET: "b", FIREBASE_WEB_API_KEY: "c" } as unknown as NodeJS.ProcessEnv)).not.toBeNull();
    expect(webAuthConfig({ GOOGLE_WEB_CLIENT_ID: "a" } as unknown as NodeJS.ProcessEnv)).toBeNull();
  });
});

describe("Stripe：パラメーターと署名", () => {
  it("入れ子・配列は、Stripeの形式にする。値のないキーは省く", () => {
    const pairs = encodeParams({ mode: "subscription", line_items: [{ price: "p", quantity: 1 }], subscription_data: { metadata: { uid: "u 1" } }, customer: undefined });
    expect(pairs).toContain("mode=subscription");
    expect(pairs).toContain(encodeURIComponent("line_items[0][price]") + "=p");
    expect(pairs).toContain(encodeURIComponent("line_items[0][quantity]") + "=1");
    expect(pairs).toContain(encodeURIComponent("subscription_data[metadata][uid]") + "=u%201");
    expect(pairs.some((p) => p.startsWith("customer"))).toBe(false);
  });

  const secret = "whsec_test";
  const body = '{"type":"customer.subscription.updated"}';
  const sign = (t: number, payload = body, key = secret) => `t=${t},v1=${createHmac("sha256", key).update(`${t}.${payload}`).digest("hex")}`;

  it("正しい署名は通り、本文・鍵・時刻が違えば拒否", () => {
    const t = 1_800_000_000;
    expect(verifyStripeSignature(body, sign(t), secret, t + 10)).toBe(true);
    expect(verifyStripeSignature(body + " ", sign(t), secret, t)).toBe(false);
    expect(verifyStripeSignature(body, sign(t, body, "other"), secret, t)).toBe(false);
    expect(verifyStripeSignature(body, sign(t), secret, t + 301)).toBe(false);
    expect(verifyStripeSignature(body, null, secret, t)).toBe(false);
    expect(verifyStripeSignature(body, "t=abc,v1=zz", secret, t)).toBe(false);
  });
});

describe("Web課金：契約と権利", () => {
  const sub = (priceId: string, status = "active") => ({ id: "sub_1", status, customer: "cus_1", items: { data: [{ price: { id: priceId }, current_period_end: 1_800_000_000 }] } });

  it("価格から、プランを決める。知らない価格は無視", () => {
    expect(planForPrice("price_support", prices)).toBe("support");
    expect(planForPrice("price_adfree", prices)).toBe("adFree");
    expect(planForPrice("price_other", prices)).toBeNull();
    expect(recordFromSubscription(sub("price_other"), prices)).toBeNull();
  });

  it("契約から、保存する形を作る", () => {
    expect(recordFromSubscription(sub("price_adfree"), prices)).toEqual({
      plan: "adFree", status: "active", currentPeriodEnd: new Date(1_800_000_000 * 1000).toISOString(), customerId: "cus_1", subscriptionId: "sub_1",
    });
  });

  it("有効なのは active と trialing だけ（支払い失敗・解約済みは無効）", () => {
    const base = { plan: "support" as const, currentPeriodEnd: null, customerId: "c", subscriptionId: "s" };
    expect(activeWebPlan({ webPlan: { ...base, status: "active" } })).toBe("support");
    expect(activeWebPlan({ webPlan: { ...base, status: "trialing" } })).toBe("support");
    for (const status of ["past_due", "canceled", "unpaid", "incomplete"]) expect(activeWebPlan({ webPlan: { ...base, status } })).toBeNull();
    expect(activeWebPlan(undefined)).toBeNull();
  });
});

describe("Webログイン", () => {
  it("Googleの認可URLには、名前だけを求める（メール・写真・Driveは求めない）", () => {
    const url = new URL(googleAuthUrl({ clientId: "cid", clientSecret: "s", firebaseApiKey: "k" }, "https://example.test/api/web/callback", "st"));
    expect(url.searchParams.get("scope")).toBe("openid profile");
    expect(url.searchParams.get("state")).toBe("st");
    expect(url.searchParams.get("redirect_uri")).toBe("https://example.test/api/web/callback");
  });

  it("Cookieは、HttpOnly・Secure・SameSite=Lax", () => {
    const header = cookieHeader("futo_session", "a b", 60);
    expect(header).toContain("HttpOnly");
    expect(header).toContain("Secure");
    expect(header).toContain("SameSite=Lax");
    expect(parseCookie("x=1; futo_session=a%20b; y=2", "futo_session")).toBe("a b");
    expect(parseCookie(null, "x")).toBeUndefined();
  });
});

import { ownerGroupKey } from "@/lib/friendShares";

describe("届いた記録のまとめ方", () => {
  it("同じ送り主・同じ受け手なら同じ値。受け手が違えば別の値。IDそのものは含まない", () => {
    const a = ownerGroupKey("owner-1", "viewer-1", true);
    expect(ownerGroupKey("owner-1", "viewer-1", true)).toBe(a);
    expect(ownerGroupKey("owner-1", "viewer-2", true)).not.toBe(a);
    expect(ownerGroupKey("owner-2", "viewer-1", true)).not.toBe(a);
    expect(a).not.toContain("owner-1");
  });

  it("名前を出さない共有は、同じ人でも、名前のある共有とは別の値（同じ人だと見破られない）", () => {
    expect(ownerGroupKey("owner-1", "viewer-1", false)).not.toBe(ownerGroupKey("owner-1", "viewer-1", true));
  });
});
