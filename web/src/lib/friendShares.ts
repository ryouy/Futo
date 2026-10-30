import { FieldPath, Timestamp, type DocumentData } from "firebase-admin/firestore";
import { addDays, now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { blockRef, friendships, isBlockedBetween } from "./friends";
import { consumeDaily, readDaily } from "./limits";
import { snapshotFrom, type FriendSharePayload, type StatsSnapshot } from "./schema";
import type { z } from "zod";
import type { friendShareUpdatePayload } from "./schema";
import { pairKey } from "./tokens";
import { loadActiveUser, userRef } from "./users";

export const FRIEND_SHARE_TTL_DAYS = 30;
export const MAX_FRIEND_SHARES_PER_DAY = 20;
/** 継続共有の更新は、1日48回まで（アプリを開くたびの更新を想定）。 */
export const MAX_FRIEND_SHARE_UPDATES_PER_DAY = 48;

const friendShares = () => db().collection("friendShares");
const iso = (ts: Timestamp) => ts.toDate().toISOString();

/**
 * フレンド限定共有を作る。選ばれた相手が、いま承認済みのフレンドで、ブロックされていないことを検証する。
 * 新しいフレンドへ、過去のカードを自動で公開しない（受信者は作成時に明示的に選ぶ）。
 */
export async function createFriendShare(uid: string, payload: FriendSharePayload) {
  const user = await loadActiveUser(uid);
  const recipients = [...new Set(payload.recipientUids)];
  if (recipients.includes(uid)) throw new ApiError(400, "invalid_recipient");
  const t = now();
  const expiresAt = Timestamp.fromDate(addDays(t, FRIEND_SHARE_TTL_DAYS));
  const opRef = db().collection("operationKeys").doc(`${uid}_${payload.idempotencyKey}`);
  const ref = friendShares().doc();

  return db().runTransaction(async (tx) => {
    const op = await tx.get(opRef);
    if (op.exists) return { shareId: op.data()?.shareId as string, replay: true, expiresAt: iso(op.data()?.expiresAt) };
    const counter = await readDaily(tx, uid, "friendShare");
    const grants: Record<string, number> = {};
    for (const recipient of recipients) {
      const friendship = await tx.get(friendships().doc(pairKey(uid, recipient)));
      if (!friendship.exists || friendship.data()?.status !== "active") throw new ApiError(403, "not_friends");
      if (await isBlockedBetween(tx, uid, recipient)) throw new ApiError(403, "not_friends");
      grants[recipient] = friendship.data()?.generation as number;
    }
    consumeDaily(tx, counter, uid, "friendShare", MAX_FRIEND_SHARES_PER_DAY);
    tx.set(ref, {
      ownerUid: uid,
      kind: "friend",
      status: "active",
      recipientUids: recipients,
      grants, // 受信者ごとの「関係の世代」。解除・再承認で世代が変わると、古い権限は復活しない
      ownerName: payload.showName ? user.displayName : null,
      stats: snapshotFrom(payload),
      selected: { counts: Boolean(payload.counts), purposes: Boolean(payload.purposes), feelings: Boolean(payload.feelings), apps: Boolean(payload.apps), restriction: Boolean(payload.restriction), phrase: Boolean(payload.phraseId) },
      createdAt: Timestamp.fromDate(t),
      updatedAt: Timestamp.fromDate(t),
      expiresAt,
    });
    tx.set(opRef, { uid, shareId: ref.id, expiresAt, createdAt: Timestamp.fromDate(t) });
    return { shareId: ref.id, replay: false, expiresAt: iso(expiresAt) };
  });
}

/** 受信者としていま読めるか：有効・期限内・フレンドが現在も有効で世代が一致・ブロックなし・作成者が削除中でない。 */
async function canRead(data: DocumentData, viewerUid: string): Promise<boolean> {
  if (data.status !== "active" || (data.expiresAt as Timestamp).toMillis() <= now().getTime()) return false;
  if (!(data.recipientUids as string[]).includes(viewerUid)) return false;
  const ownerUid = data.ownerUid as string;
  const [friendship, owner, b1, b2] = await db().getAll(friendships().doc(pairKey(ownerUid, viewerUid)), userRef(ownerUid), blockRef(ownerUid, viewerUid), blockRef(viewerUid, ownerUid));
  if (!friendship.exists || friendship.data()?.status !== "active") return false;
  if (friendship.data()?.generation !== (data.grants as Record<string, number>)[viewerUid]) return false;
  if (!owner.exists || owner.data()?.status !== "active") return false;
  return !b1.exists && !b2.exists;
}

export async function getFriendShare(uid: string, shareId: string) {
  const snap = await friendShares().doc(shareId).get();
  const data = snap.data();
  if (!data) throw new ApiError(404, "not_found");
  const isOwner = data.ownerUid === uid;
  if (!isOwner && !(await canRead(data, uid))) throw new ApiError(404, "not_found");
  return {
    id: snap.id,
    ownerName: (data.ownerName as string | null) ?? null,
    isOwner,
    createdAt: iso(data.createdAt),
    updatedAt: iso((data.updatedAt ?? data.createdAt) as Timestamp),
    expiresAt: iso(data.expiresAt),
    status: data.status as string,
    stats: data.stats as StatsSnapshot,
  };
}

/** 受け取ったカードの一覧（いま読めるものだけ）。 */
export async function listReceivedFriendShares(uid: string, limit = 20) {
  const snap = await friendShares()
    .where("recipientUids", "array-contains", uid)
    .orderBy("createdAt", "desc")
    .limit(Math.min(Math.max(limit, 1), 20))
    .get();
  const items = [];
  for (const doc of snap.docs) {
    const data = doc.data();
    if (await canRead(data, uid)) {
      items.push({ id: doc.id, ownerName: (data.ownerName as string | null) ?? null, period: (data.stats as StatsSnapshot).period, createdAt: iso(data.createdAt), updatedAt: iso((data.updatedAt ?? data.createdAt) as Timestamp), expiresAt: iso(data.expiresAt) });
    }
  }
  return { items };
}

export async function listSentFriendShares(uid: string, limit = 20) {
  const snap = await friendShares().where("ownerUid", "==", uid).orderBy("createdAt", "desc").limit(Math.min(Math.max(limit, 1), 20)).get();
  return {
    items: snap.docs.map((doc) => {
      const data = doc.data();
      return {
        id: doc.id,
        period: (data.stats as StatsSnapshot).period,
        recipientCount: (data.recipientUids as string[]).length,
        createdAt: iso(data.createdAt),
        updatedAt: iso((data.updatedAt ?? data.createdAt) as Timestamp),
        expiresAt: iso(data.expiresAt),
        status: data.status === "revoked" ? "revoked" : (data.expiresAt as Timestamp).toMillis() <= now().getTime() ? "expired" : "active",
      };
    }),
  };
}

export async function revokeFriendShare(uid: string, shareId: string): Promise<void> {
  const ref = friendShares().doc(shareId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()?.ownerUid !== uid) throw new ApiError(404, "not_found");
    tx.update(ref, { status: "revoked", revokedAt: Timestamp.fromDate(now()) });
  });
}

/**
 * 継続共有の更新：作成者が、統計を最新のものに差し替える。受信者は変わらない。
 * 取り消し済み・期限切れの共有は、更新しない（期限切れは「もう一度共有」で作り直す）。
 * 更新のたびに、期限をその時点から30日に延ばす。更新されなくなって30日たつと、自動で見えなくなる。
 */
export async function updateFriendShare(uid: string, shareId: string, payload: z.infer<typeof friendShareUpdatePayload>) {
  const user = await loadActiveUser(uid);
  const t = now();
  const expiresAt = Timestamp.fromDate(addDays(t, FRIEND_SHARE_TTL_DAYS));
  const ref = friendShares().doc(shareId);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    if (!data || data.ownerUid !== uid || data.status !== "active") throw new ApiError(404, "not_found");
    if ((data.expiresAt as Timestamp).toMillis() <= t.getTime()) throw new ApiError(410, "expired");
    const counter = await readDaily(tx, uid, "friendShareUpdate");
    consumeDaily(tx, counter, uid, "friendShareUpdate", MAX_FRIEND_SHARE_UPDATES_PER_DAY);
    tx.update(ref, {
      ownerName: payload.showName ? user.displayName : null,
      stats: snapshotFrom(payload),
      selected: { counts: Boolean(payload.counts), purposes: Boolean(payload.purposes), feelings: Boolean(payload.feelings), apps: Boolean(payload.apps), restriction: Boolean(payload.restriction), phrase: Boolean(payload.phraseId) },
      updatedAt: Timestamp.fromDate(t),
      expiresAt,
    });
    return { shareId, updatedAt: iso(Timestamp.fromDate(t)), expiresAt: iso(expiresAt) };
  });
}
