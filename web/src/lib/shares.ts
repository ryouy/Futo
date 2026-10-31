import { Timestamp, type DocumentData } from "firebase-admin/firestore";
import { addDays, now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { consumeDaily, readDaily } from "./limits";
import { assertNotLimited, recordFailure } from "./rateLimit";
import { snapshotFrom, type StatsSnapshot, type WebSharePayload } from "./schema";
import { hashToken, looksLikeToken, newToken } from "./tokens";
import { loadActiveUser, userRef } from "./users";

export const MAX_ACTIVE_SHARES = 20;
export const MAX_SHARES_PER_DAY = 20;

const shares = () => db().collection("shares");
const shareTokens = () => db().collection("shareTokens");
const iso = (ts: Timestamp) => ts.toDate().toISOString();

type ShareStatus = "active" | "revoked" | "expired";
const statusOf = (data: DocumentData): ShareStatus =>
  data.status === "revoked" ? "revoked" : (data.expiresAt as Timestamp).toMillis() <= now().getTime() ? "expired" : "active";

export interface CreatedShare {
  shareId: string;
  /** 作成時だけ返る生トークン（サーバーにはハッシュしか残らない）。再送で作成済みだった場合は null */
  token: string | null;
  replay: boolean;
  expiresAt: string;
}

export async function createWebShare(uid: string, payload: WebSharePayload): Promise<CreatedShare> {
  const user = await loadActiveUser(uid);
  const t = now();
  const expiresAt = Timestamp.fromDate(addDays(t, payload.expiresInDays));
  const opRef = db().collection("operationKeys").doc(`${uid}_${payload.idempotencyKey}`);
  const shareRef = shares().doc();
  const token = newToken();
  const hash = hashToken(token);

  return db().runTransaction(async (tx) => {
    // ---- 読み取り（書き込みより先に済ませる）
    const op = await tx.get(opRef);
    if (op.exists) {
      const previous = op.data() as { shareId: string; expiresAt: Timestamp };
      return { shareId: previous.shareId, token: null, replay: true, expiresAt: iso(previous.expiresAt) };
    }
    const counter = await readDaily(tx, uid, "webShare");
    const active = await tx.get(
      shares().where("ownerUid", "==", uid).where("status", "==", "active").where("expiresAt", ">", Timestamp.fromDate(t)).limit(MAX_ACTIVE_SHARES),
    );
    if (active.size >= MAX_ACTIVE_SHARES) throw new ApiError(429, "too_many_shares");

    // ---- 書き込み
    consumeDaily(tx, counter, uid, "webShare", MAX_SHARES_PER_DAY);
    tx.set(shareRef, {
      ownerUid: uid,
      kind: "web",
      status: "active",
      // 作成時点のコピー。表示名を変えても、過去の共有は自動では変わらない
      displayName: payload.showName ? user.displayName : null,
      stats: snapshotFrom(payload),
      selected: {
        counts: Boolean(payload.counts),
        purposes: Boolean(payload.purposes),
        feelings: Boolean(payload.feelings),
        restriction: Boolean(payload.restriction),
        phrase: Boolean(payload.phraseId),
      },
      tokenHash: hash,
      createdAt: Timestamp.fromDate(t),
      expiresAt,
    });
    tx.set(shareTokens().doc(hash), { shareId: shareRef.id });
    tx.set(opRef, { uid, shareId: shareRef.id, expiresAt, createdAt: Timestamp.fromDate(t) });
    return { shareId: shareRef.id, token, replay: false, expiresAt: iso(expiresAt) };
  });
}

export async function listShares(uid: string, limit: number, cursor?: string) {
  const size = Math.min(Math.max(limit, 1), 20);
  let query = shares().where("ownerUid", "==", uid).orderBy("createdAt", "desc").limit(size);
  if (cursor) {
    const ms = Number(cursor);
    if (!Number.isFinite(ms)) throw new ApiError(400, "invalid_cursor");
    query = query.startAfter(Timestamp.fromMillis(ms));
  }
  const snap = await query.get();
  const items = snap.docs.map((doc) => {
    const data = doc.data();
    return {
      id: doc.id,
      period: (data.stats as StatsSnapshot).period,
      periodStart: (data.stats as StatsSnapshot).periodStart,
      periodEnd: (data.stats as StatsSnapshot).periodEnd,
      selected: data.selected,
      createdAt: iso(data.createdAt),
      expiresAt: iso(data.expiresAt),
      status: statusOf(data),
    };
  });
  const last = snap.docs[snap.docs.length - 1];
  const next = snap.size === size && last ? String((last.data().createdAt as Timestamp).toMillis()) : null;
  return { items, next };
}

/** 所有者だけが取消できる。他人のIDは「存在しない」と同じ応答にして、存在を知らせない。 */
/** 自分が作った共有の中身を、本人が確かめる（アプリの中で、リンクを開かずに見られるように）。取り消した共有は、返さない。 */
export async function getOwnShare(uid: string, shareId: string): Promise<PublicShare & { id: string; status: string }> {
  const snap = await shares().doc(shareId).get();
  const data = snap.data();
  if (!data || data.ownerUid !== uid || data.status === "revoked") throw new ApiError(404, "not_found");
  return {
    id: snap.id,
    status: statusOf(data),
    displayName: (data.displayName as string | null) ?? null,
    createdAt: iso(data.createdAt),
    expiresAt: iso(data.expiresAt),
    stats: data.stats as StatsSnapshot,
  };
}

export async function revokeShare(uid: string, shareId: string): Promise<void> {
  const ref = shares().doc(shareId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()?.ownerUid !== uid) throw new ApiError(404, "not_found");
    tx.delete(shareTokens().doc(snap.data()?.tokenHash as string));
    tx.update(ref, { status: "revoked", revokedAt: Timestamp.fromDate(now()) });
  });
}

/** リンクの再発行：新しいトークンを作り、同じトランザクションで旧トークンを無効化する。 */
export async function rotateShare(uid: string, shareId: string): Promise<{ token: string; expiresAt: string }> {
  const ref = shares().doc(shareId);
  const token = newToken();
  const hash = hashToken(token);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()?.ownerUid !== uid) throw new ApiError(404, "not_found");
    const data = snap.data() as DocumentData;
    if (statusOf(data) !== "active") throw new ApiError(409, "not_active");
    tx.delete(shareTokens().doc(data.tokenHash as string));
    tx.set(shareTokens().doc(hash), { shareId });
    tx.update(ref, { tokenHash: hash });
    return { token, expiresAt: iso(data.expiresAt) };
  });
}

export interface PublicShare {
  displayName: string | null;
  createdAt: string;
  expiresAt: string;
  stats: StatsSnapshot;
}

/**
 * 匿名の閲覧。毎回、期限・取消・所有者の状態を確認する（キャッシュしない）。
 * 不正・期限切れ・削除済みは、すべて同じ「利用できません」にする。
 */
export async function getPublicShare(token: string, clientKeyValue: string): Promise<PublicShare> {
  await assertNotLimited(clientKeyValue, "lookup");
  const unavailable = async () => {
    await recordFailure(clientKeyValue, "lookup");
    return new ApiError(404, "unavailable");
  };
  if (!looksLikeToken(token)) throw await unavailable();
  const tokenSnap = await shareTokens().doc(hashToken(token)).get();
  if (!tokenSnap.exists) throw await unavailable();
  const shareSnap = await shares().doc(tokenSnap.data()?.shareId as string).get();
  if (!shareSnap.exists) throw await unavailable();
  const data = shareSnap.data() as DocumentData;
  if (statusOf(data) !== "active") throw await unavailable();
  const owner = await userRef(data.ownerUid as string).get();
  if (!owner.exists || owner.data()?.status !== "active") throw await unavailable();
  return {
    displayName: (data.displayName as string | null) ?? null,
    createdAt: iso(data.createdAt),
    expiresAt: iso(data.expiresAt),
    stats: data.stats as StatsSnapshot,
  };
}

/** 匿名通報の対象を、トークンから特定する（作成者には知らせない）。 */
export async function shareIdForToken(token: string): Promise<string | null> {
  if (!looksLikeToken(token)) return null;
  const snap = await shareTokens().doc(hashToken(token)).get();
  return snap.exists ? (snap.data()?.shareId as string) : null;
}
