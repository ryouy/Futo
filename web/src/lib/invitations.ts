import { Timestamp, type DocumentData } from "firebase-admin/firestore";
import { addHours, now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { consumeDaily, readDaily } from "./limits";
import { assertNotLimited, recordFailure } from "./rateLimit";
import { deriveInviteCode, hashToken, looksLikeToken, newToken, normalizeCode } from "./tokens";
import { loadActiveUser, userRef } from "./users";

export const INVITE_TTL_HOURS = 24;
export const MAX_INVITES_PER_DAY = 10;

export const invitations = () => db().collection("invitations");
export const invitationTokens = () => db().collection("invitationTokens");
const iso = (ts: Timestamp) => ts.toDate().toISOString();

/** コードのハッシュは、リンクのトークンとは別の名前空間にする。 */
export const codeHash = (code: string) => hashToken(`code:${normalizeCode(code)}`);

/** 24時間有効・成功申請1件限りの招待。統計共有のトークンとは完全に別。 */
export async function createInvitation(uid: string) {
  await loadActiveUser(uid);
  const t = now();
  const expiresAt = Timestamp.fromDate(addHours(t, INVITE_TTL_HOURS));
  const ref = invitations().doc();
  const token = newToken();
  const code = deriveInviteCode(token);
  const tokenHash = hashToken(token);
  const codeHashValue = codeHash(code);

  await db().runTransaction(async (tx) => {
    const counter = await readDaily(tx, uid, "invitation");
    consumeDaily(tx, counter, uid, "invitation", MAX_INVITES_PER_DAY);
    tx.set(ref, { inviterUid: uid, status: "open", tokenHash, codeHash: codeHashValue, createdAt: Timestamp.fromDate(t), expiresAt });
    tx.set(invitationTokens().doc(tokenHash), { inviteId: ref.id, kind: "link" });
    tx.set(invitationTokens().doc(codeHashValue), { inviteId: ref.id, kind: "code" });
  });
  return { inviteId: ref.id, token, code, expiresAt: iso(expiresAt) };
}

/** 招待者だけが取り消せる。 */
export async function cancelInvitation(uid: string, inviteId: string): Promise<void> {
  const ref = invitations().doc(inviteId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()?.inviterUid !== uid) throw new ApiError(404, "not_found");
    const data = snap.data() as DocumentData;
    tx.delete(invitationTokens().doc(data.tokenHash as string));
    tx.delete(invitationTokens().doc(data.codeHash as string));
    tx.update(ref, { status: "revoked" });
  });
}

/**
 * 招待ページの表示用。GETでは、申請も、使用済みへの変更もしない。
 * 返すのは、招待者の仮名と有効状態だけ（メール・UIDは出さない）。
 */
export async function getPublicInvitation(token: string, clientKeyValue: string) {
  await assertNotLimited(clientKeyValue, "lookup");
  const unavailable = async () => {
    await recordFailure(clientKeyValue, "lookup");
    return new ApiError(404, "unavailable");
  };
  if (!looksLikeToken(token)) throw await unavailable();
  const tokenSnap = await invitationTokens().doc(hashToken(token)).get();
  if (!tokenSnap.exists || tokenSnap.data()?.kind !== "link") throw await unavailable();
  const inv = await invitations().doc(tokenSnap.data()?.inviteId as string).get();
  if (!inv.exists) throw await unavailable();
  const data = inv.data() as DocumentData;
  if (data.status !== "open" || (data.expiresAt as Timestamp).toMillis() <= now().getTime()) throw await unavailable();
  const inviter = await userRef(data.inviterUid as string).get();
  if (!inviter.exists || inviter.data()?.status !== "active") throw await unavailable();
  // 招待ページには、同じ招待のコードも見せる。トークンから導いたコードが、保存したものと一致するときだけ（古い招待は出さない）
  const derived = deriveInviteCode(token);
  const code = data.codeHash === codeHash(derived) ? derived : null;
  return { inviterName: inviter.data()?.displayName as string, expiresAt: iso(data.expiresAt), code };
}
