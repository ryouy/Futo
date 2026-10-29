import { FieldPath, FieldValue, type Query } from "firebase-admin/firestore";
import { now } from "./clock";
import { adminAuth, db } from "./firebase";
import { ApiError } from "./http";
import { sha256 } from "./tokens";
import { userRef } from "./users";

/** 再認証の有効時間（秒）。アカウント削除は、直近にサインインした本人にだけ許す。 */
export const RECENT_LOGIN_SECONDS = 5 * 60;

const BATCH = 100;

/** 削除の各ステップ。すべて冪等で、途中で失敗しても、同じ呼び出しで再開できる。 */
const STEPS = ["shares", "invitations", "friendRequests", "friendships", "friendShares", "blocks", "reports", "counters", "profile", "auth"] as const;
type Step = (typeof STEPS)[number];

async function drain(query: Query, each: (doc: FirebaseFirestore.QueryDocumentSnapshot) => Promise<void> | void, deadline: number): Promise<boolean> {
  for (;;) {
    const snap = await query.limit(BATCH).get();
    if (snap.empty) return true;
    for (const doc of snap.docs) await each(doc);
    if (Date.now() > deadline) return false;
  }
}

export interface DeletionOptions {
  budgetMs?: number;
  /** テスト用：指定のステップで失敗させる（再開できることの確認） */
  failAtStep?: Step;
}

export async function beginAccountDeletion(uid: string, authTime: number): Promise<void> {
  const ref = userRef(uid);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.data()?.status === "deleting") return; // 再開は、再認証なしで続けられる
    if (Math.floor(now().getTime() / 1000) - authTime > RECENT_LOGIN_SECONDS) throw new ApiError(401, "recent_login_required");
    // 先に「削除中」にする。以降、この人の共有・招待・フレンド関係は、残っていても、誰からも読めない
    if (snap.exists) tx.update(ref, { status: "deleting", deletingAt: FieldValue.serverTimestamp() });
    else tx.set(ref, { displayName: "", status: "deleting", deletingAt: FieldValue.serverTimestamp() });
  });
}

/** @returns 完了なら "deleted"、時間切れ・未完了なら "in_progress"（呼び出し側が再度呼ぶ） */
export async function purgeUserData(uid: string, options: DeletionOptions = {}): Promise<"deleted" | "in_progress"> {
  const deadline = Date.now() + (options.budgetMs ?? 7_000);
  const d = db();
  const guard = (step: Step) => {
    if (options.failAtStep === step) throw new Error(`injected_failure_${step}`);
  };

  guard("shares");
  if (!(await drain(d.collection("shares").where("ownerUid", "==", uid), async (doc) => {
    await d.collection("shareTokens").doc(doc.data().tokenHash).delete();
    await doc.ref.delete();
  }, deadline))) return "in_progress";

  guard("invitations");
  if (!(await drain(d.collection("invitations").where("inviterUid", "==", uid), async (doc) => {
    await d.collection("invitationTokens").doc(doc.data().tokenHash).delete();
    await d.collection("invitationTokens").doc(doc.data().codeHash).delete();
    await doc.ref.delete();
  }, deadline))) return "in_progress";

  guard("friendRequests");
  for (const field of ["inviterUid", "requesterUid"]) {
    if (!(await drain(d.collection("friendRequests").where(field, "==", uid), (doc) => void doc.ref.delete(), deadline))) return "in_progress";
  }

  guard("friendships");
  if (!(await drain(d.collection("friendships").where("members", "array-contains", uid), (doc) => void doc.ref.delete(), deadline))) return "in_progress";

  guard("friendShares");
  if (!(await drain(d.collection("friendShares").where("ownerUid", "==", uid), (doc) => void doc.ref.delete(), deadline))) return "in_progress";
  if (!(await drain(d.collection("friendShares").where("recipientUids", "array-contains", uid), async (doc) => {
    await doc.ref.update("recipientUids", FieldValue.arrayRemove(uid), new FieldPath("grants", uid), FieldValue.delete());
  }, deadline))) return "in_progress";

  guard("blocks");
  for (const field of ["blockerUid", "blockedUid"]) {
    if (!(await drain(d.collection("blocks").where(field, "==", uid), (doc) => void doc.ref.delete(), deadline))) return "in_progress";
  }

  // 通報は、運営の確認のため残すが、通報者のUIDは、ハッシュに置き換える（保持の方針は PHASE4_SETUP.md）
  guard("reports");
  if (!(await drain(d.collection("reports").where("reporterUid", "==", uid), (doc) => void doc.ref.update({ reporterUid: `deleted:${sha256(uid).slice(0, 16)}` }), deadline))) return "in_progress";

  guard("counters");
  for (const name of ["usageLimits", "operationKeys"]) {
    if (!(await drain(d.collection(name).where("uid", "==", uid), (doc) => void doc.ref.delete(), deadline))) return "in_progress";
  }

  guard("profile");
  await userRef(uid).delete();

  // Authは最後。先に消して、管理不能にしない
  guard("auth");
  try {
    await adminAuth().deleteUser(uid);
  } catch (error) {
    if ((error as { code?: string }).code !== "auth/user-not-found") throw error;
  }
  return "deleted";
}
