import { Timestamp } from "firebase-admin/firestore";
import { now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { consumeDaily, readDaily } from "./limits";
import { assertNotLimited, recordFailure } from "./rateLimit";
import { shareIdForToken } from "./shares";
import { loadActiveUser } from "./users";

export const MAX_REPORTS_PER_DAY = 20;
const reports = () => db().collection("reports");

/**
 * 通報（ログイン済み）。対象IDと定型理由だけを保存する。自由記述・画像は受け取らない。
 * 通報は誰からも読み取れるAPIを持たない（クライアントのFirestore直接アクセスも拒否）。運営がコンソールで確認する。
 */
export async function createReport(uid: string, input: { targetType: string; targetId: string; reason: string }) {
  await loadActiveUser(uid);
  const ref = reports().doc();
  await db().runTransaction(async (tx) => {
    const counter = await readDaily(tx, uid, "report");
    consumeDaily(tx, counter, uid, "report", MAX_REPORTS_PER_DAY);
    tx.set(ref, { reporterUid: uid, targetType: input.targetType, targetId: input.targetId, reason: input.reason, status: "open", createdAt: Timestamp.fromDate(now()) });
  });
  return { reportId: ref.id };
}

/** 匿名のWeb通報：共有リンクのトークンを持つ人が、IP単位の持続する制限つきで送れる。 */
export async function createPublicReport(token: string, reason: string, clientKeyValue: string) {
  await assertNotLimited(clientKeyValue, "report");
  const shareId = await shareIdForToken(token);
  if (!shareId) {
    await recordFailure(clientKeyValue, "lookup");
    throw new ApiError(404, "unavailable");
  }
  await recordFailure(clientKeyValue, "report"); // 送るたびに数える（成功も含めて、1時間5件まで）
  const ref = reports().doc();
  await ref.set({ reporterUid: null, targetType: "share", targetId: shareId, reason, status: "open", createdAt: Timestamp.fromDate(now()) });
  return { reportId: ref.id };
}
