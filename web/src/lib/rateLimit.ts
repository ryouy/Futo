import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { sha256 } from "./tokens";

/**
 * 匿名APIの総当たり対策。サーバーレスのメモリ変数ではなく、Firestoreに持続する失敗カウンターを使う。
 * IPは、ソルト付きのハッシュにして保存する（生のIPは保存しない）。
 * 1時間あたりの失敗が上限に達したら、その間は429を返す。成功時は書き込まない（無料枠を節約）。
 */
const LIMITS: Record<string, number> = { lookup: 20, code: 10 };

export function clientKeyFromHeaders(headers: { get(name: string): string | null }): string {
  const forwarded = headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || headers.get("x-real-ip") || "unknown";
  return sha256(`${process.env.RATE_LIMIT_SALT ?? "futo"}:${ip}`).slice(0, 32);
}

export const clientKey = (req: Request): string => clientKeyFromHeaders(req.headers);

const hourKey = () => Math.floor(now().getTime() / 3_600_000).toString();
const refFor = (key: string, scope: string) => db().collection("rateLimits").doc(`${scope}_${key}_${hourKey()}`);

export async function assertNotLimited(key: string, scope: keyof typeof LIMITS): Promise<void> {
  const snap = await refFor(key, scope).get();
  if (snap.exists && (snap.data()?.count as number) >= LIMITS[scope]) throw new ApiError(429, "rate_limited");
}

export async function recordFailure(key: string, scope: keyof typeof LIMITS): Promise<void> {
  await refFor(key, scope).set(
    { scope, count: FieldValue.increment(1), expiresAt: Timestamp.fromDate(new Date(now().getTime() + 2 * 3_600_000)) },
    { merge: true },
  );
}
