import { createHmac, timingSafeEqual } from "node:crypto";
import { ApiError } from "./http";

/**
 * Stripe の REST API を、依存パッケージなしで呼ぶ小さな窓口。
 * キー類は環境変数だけに置く（リポジトリには入れない）。
 */
export interface BillingConfig {
  secretKey: string;
  webhookSecret: string;
  priceAdFree: string;
  priceSupport: string;
}

/** 決済に必要な設定がそろっているか。特定商取引法の表記（連絡先）が未設定のときは、決済を始めない。 */
export function billingConfig(env: NodeJS.ProcessEnv = process.env): BillingConfig | null {
  const secretKey = env.STRIPE_SECRET_KEY;
  const webhookSecret = env.STRIPE_WEBHOOK_SECRET;
  const priceAdFree = env.STRIPE_PRICE_ADFREE;
  const priceSupport = env.STRIPE_PRICE_SUPPORT;
  if (!secretKey || !webhookSecret || !priceAdFree || !priceSupport) return null;
  if (!env.LEGAL_SELLER_NAME || !env.LEGAL_ADDRESS || !env.LEGAL_CONTACT) return null;
  return { secretKey, webhookSecret, priceAdFree, priceSupport };
}

/** Stripe へのフォーム形式のパラメーター（入れ子は、a[b][0]=… の形にする）。 */
export function encodeParams(params: Record<string, unknown>, prefix = ""): string[] {
  const pairs: string[] = [];
  for (const [key, value] of Object.entries(params)) {
    if (value === undefined || value === null) continue;
    const name = prefix ? `${prefix}[${key}]` : key;
    if (Array.isArray(value)) {
      value.forEach((item, index) => {
        if (item !== null && typeof item === "object") pairs.push(...encodeParams(item as Record<string, unknown>, `${name}[${index}]`));
        else pairs.push(`${encodeURIComponent(`${name}[${index}]`)}=${encodeURIComponent(String(item))}`);
      });
    } else if (typeof value === "object") {
      pairs.push(...encodeParams(value as Record<string, unknown>, name));
    } else {
      pairs.push(`${encodeURIComponent(name)}=${encodeURIComponent(String(value))}`);
    }
  }
  return pairs;
}

export async function stripeRequest<T>(config: BillingConfig, method: "GET" | "POST" | "DELETE", path: string, params: Record<string, unknown> = {}, fetcher: typeof fetch = fetch): Promise<T> {
  const body = encodeParams(params).join("&");
  const url = `https://api.stripe.com/v1${path}${method === "GET" && body ? `?${body}` : ""}`;
  const response = await fetcher(url, {
    method,
    headers: { authorization: `Bearer ${config.secretKey}`, ...(method === "POST" ? { "content-type": "application/x-www-form-urlencoded" } : {}) },
    ...(method === "POST" ? { body } : {}),
  });
  const data = (await response.json().catch(() => ({}))) as { error?: { code?: string } } & T;
  if (!response.ok) {
    const code = data.error?.code;
    if (code === "resource_missing") throw new ApiError(404, "not_found");
    throw new ApiError(502, "billing_unavailable");
  }
  return data;
}

/**
 * Webhook の署名を検証する（`Stripe-Signature: t=…,v1=…`）。
 * 本文は、解釈する前の文字列のまま使う。許容する時間のずれは、既定で5分。
 */
export function verifyStripeSignature(rawBody: string, header: string | null, secret: string, nowSeconds: number, toleranceSeconds = 300): boolean {
  if (!header) return false;
  let timestamp = "";
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const [key, value] = part.split("=");
    if (key === "t") timestamp = value ?? "";
    if (key === "v1" && value) signatures.push(value);
  }
  const t = Number(timestamp);
  if (!timestamp || !Number.isFinite(t) || Math.abs(nowSeconds - t) > toleranceSeconds) return false;
  const expected = createHmac("sha256", secret).update(`${timestamp}.${rawBody}`).digest("hex");
  const expectedBuffer = Buffer.from(expected, "hex");
  return signatures.some((signature) => {
    const candidate = Buffer.from(signature, "hex");
    return candidate.length === expectedBuffer.length && timingSafeEqual(candidate, expectedBuffer);
  });
}
