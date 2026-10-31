import { Timestamp, type DocumentData, type Transaction } from "firebase-admin/firestore";
import { addDays, now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { codeHash, invitationTokens, invitations } from "./invitations";
import { assertNotLimited, recordFailure } from "./rateLimit";
import { hashToken, looksLikeCode, looksLikeToken, normalizeCode, pairKey } from "./tokens";
import { activeProfiles, loadActiveUser, userRef } from "./users";

export const MAX_FRIENDS = 50;
export const MAX_PENDING_REQUESTS = 20;
export const REQUEST_TTL_DAYS = 7;

export const friendRequests = () => db().collection("friendRequests");
export const friendships = () => db().collection("friendships");
export const blocks = () => db().collection("blocks");
const iso = (ts: Timestamp) => ts.toDate().toISOString();

export const blockRef = (blocker: string, blocked: string) => blocks().doc(`${blocker}_${blocked}`);

/** どちらの向きでもブロックがあれば true（ブロックした事実は、相手には知らせない）。 */
export async function isBlockedBetween(tx: Transaction | null, a: string, b: string): Promise<boolean> {
  const refs = [blockRef(a, b), blockRef(b, a)];
  const snaps = tx ? await Promise.all(refs.map((r) => tx.get(r))) : await db().getAll(...refs);
  return snaps.some((s) => s.exists);
}

const isPendingValid = (data: DocumentData) =>
  data.status === "pending" && (data.expiresAt as Timestamp).toMillis() > now().getTime();

async function countFriends(tx: Transaction, uid: string): Promise<number> {
  const snap = await tx.get(friendships().where("members", "array-contains", uid).where("status", "==", "active").limit(MAX_FRIENDS));
  return snap.size;
}

/**
 * 招待のトークン（またはコード）で、フレンド申請を作る。
 * 期限・残り回数・自己招待・既存関係・ブロック・上限を、1つのトランザクションで検証し、招待を消費する。
 */
export async function createFriendRequest(uid: string, input: { token?: string; code?: string }, clientKeyValue: string) {
  await loadActiveUser(uid);
  const byCode = typeof input.code === "string";
  const raw = byCode ? normalizeCode(input.code as string) : (input.token as string);
  if (byCode ? !looksLikeCode(raw) : !looksLikeToken(raw)) {
    await recordFailure(uid, "code");
    throw new ApiError(404, "invalid_invitation");
  }
  await assertNotLimited(uid, "code"); // 試行回数の制限（コードの総当たり対策）
  const lookupHash = byCode ? codeHash(raw) : hashToken(raw);

  try {
    return await db().runTransaction(async (tx) => {
      const tokenSnap = await tx.get(invitationTokens().doc(lookupHash));
      if (!tokenSnap.exists) throw new ApiError(404, "invalid_invitation");
      const invRef = invitations().doc(tokenSnap.data()?.inviteId as string);
      const invSnap = await tx.get(invRef);
      const inv = invSnap.data() as DocumentData | undefined;
      if (!inv || inv.status !== "open" || (inv.expiresAt as Timestamp).toMillis() <= now().getTime()) {
        throw new ApiError(410, "invitation_unavailable");
      }
      const inviterUid = inv.inviterUid as string;
      if (inviterUid === uid) throw new ApiError(400, "self_invite");

      const inviter = await tx.get(userRef(inviterUid));
      if (!inviter.exists || inviter.data()?.status !== "active") throw new ApiError(410, "invitation_unavailable");
      if (await isBlockedBetween(tx, uid, inviterUid)) throw new ApiError(403, "unavailable");

      const key = pairKey(uid, inviterUid);
      const friendship = await tx.get(friendships().doc(key));
      if (friendship.exists && friendship.data()?.status === "active") throw new ApiError(409, "already_friends");
      const existing = await tx.get(friendRequests().doc(key));
      if (existing.exists && isPendingValid(existing.data() as DocumentData)) throw new ApiError(409, "request_pending");

      if ((await countFriends(tx, uid)) >= MAX_FRIENDS || (await countFriends(tx, inviterUid)) >= MAX_FRIENDS) {
        throw new ApiError(409, "friend_limit");
      }
      const pending = await tx.get(friendRequests().where("inviterUid", "==", inviterUid).where("status", "==", "pending").limit(MAX_PENDING_REQUESTS));
      if (pending.docs.filter((d) => isPendingValid(d.data())).length >= MAX_PENDING_REQUESTS) {
        throw new ApiError(429, "too_many_requests");
      }

      const t = now();
      tx.update(invRef, { status: "consumed", consumedBy: uid, consumedAt: Timestamp.fromDate(t) });
      tx.set(friendRequests().doc(key), {
        pairKey: key,
        requesterUid: uid,
        inviterUid,
        inviteId: invRef.id,
        status: "pending",
        createdAt: Timestamp.fromDate(t),
        expiresAt: Timestamp.fromDate(addDays(t, REQUEST_TTL_DAYS)),
      });
      return { requestId: key, status: "pending" as const };
    });
  } catch (error) {
    if (error instanceof ApiError && (error.status === 404 || error.status === 410)) await recordFailure(uid, "code");
    throw error;
  }
}

/** 招待者だけが承認できる。承認の後に初めてフレンドになる。 */
export async function acceptFriendRequest(uid: string, requestId: string) {
  await loadActiveUser(uid);
  const reqRef = friendRequests().doc(requestId);
  return db().runTransaction(async (tx) => {
    const reqSnap = await tx.get(reqRef);
    const req = reqSnap.data() as DocumentData | undefined;
    // 招待者以外（申請者・第三者）には、存在しないのと同じ応答
    if (!req || req.inviterUid !== uid) throw new ApiError(404, "not_found");
    if (!isPendingValid(req)) throw new ApiError(409, "not_pending");
    const requesterUid = req.requesterUid as string;
    const requester = await tx.get(userRef(requesterUid));
    if (!requester.exists || requester.data()?.status !== "active") throw new ApiError(409, "not_pending");
    if (await isBlockedBetween(tx, uid, requesterUid)) throw new ApiError(404, "not_found");
    const key = pairKey(uid, requesterUid);
    const friendship = await tx.get(friendships().doc(key));
    if (friendship.exists && friendship.data()?.status === "active") throw new ApiError(409, "already_friends");
    if ((await countFriends(tx, uid)) >= MAX_FRIENDS || (await countFriends(tx, requesterUid)) >= MAX_FRIENDS) {
      throw new ApiError(409, "friend_limit");
    }
    // 再び友達になるたびに「世代」を進める。以前の共有カードの権限は、世代が違うので復活しない。
    const generation = ((friendship.data()?.generation as number | undefined) ?? 0) + 1;
    tx.set(friendships().doc(key), {
      members: [uid, requesterUid].sort(),
      status: "active",
      generation,
      createdAt: Timestamp.fromDate(now()),
    });
    tx.update(reqRef, { status: "accepted", decidedAt: Timestamp.fromDate(now()) });
    return { friendshipId: key, friendUid: requesterUid, generation };
  });
}

/** 招待者の「見送る」。見送った後の再招待は、新しい招待が必要。 */
export async function declineFriendRequest(uid: string, requestId: string): Promise<void> {
  const reqRef = friendRequests().doc(requestId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    const req = snap.data() as DocumentData | undefined;
    if (!req || req.inviterUid !== uid) throw new ApiError(404, "not_found");
    if (!isPendingValid(req)) throw new ApiError(409, "not_pending");
    tx.update(reqRef, { status: "declined", decidedAt: Timestamp.fromDate(now()) });
  });
}

/** 申請者の取り消し。 */
export async function cancelFriendRequest(uid: string, requestId: string): Promise<void> {
  const reqRef = friendRequests().doc(requestId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(reqRef);
    const req = snap.data() as DocumentData | undefined;
    if (!req || req.requesterUid !== uid) throw new ApiError(404, "not_found");
    if (!isPendingValid(req)) throw new ApiError(409, "not_pending");
    tx.update(reqRef, { status: "cancelled", decidedAt: Timestamp.fromDate(now()) });
  });
}

export async function listFriends(uid: string) {
  const [friendSnap, incomingSnap, outgoingSnap] = await Promise.all([
    friendships().where("members", "array-contains", uid).where("status", "==", "active").limit(MAX_FRIENDS).get(),
    friendRequests().where("inviterUid", "==", uid).where("status", "==", "pending").limit(MAX_PENDING_REQUESTS).get(),
    friendRequests().where("requesterUid", "==", uid).where("status", "==", "pending").limit(MAX_PENDING_REQUESTS).get(),
  ]);
  const friendUids = friendSnap.docs.map((d) => (d.data().members as string[]).find((m) => m !== uid) as string);
  const incoming = incomingSnap.docs.filter((d) => isPendingValid(d.data()));
  const outgoing = outgoingSnap.docs.filter((d) => isPendingValid(d.data()));
  const profiles = await activeProfiles([...friendUids, ...incoming.map((d) => d.data().requesterUid as string), ...outgoing.map((d) => d.data().inviterUid as string)]);
  return {
    friends: friendSnap.docs
      .map((d, i) => ({ friendshipId: d.id, uid: friendUids[i], displayName: profiles.get(friendUids[i])?.name, avatar: profiles.get(friendUids[i])?.avatar }))
      .filter((f) => f.displayName !== undefined),
    incoming: incoming
      .map((d) => ({ requestId: d.id, uid: d.data().requesterUid as string, displayName: profiles.get(d.data().requesterUid as string)?.name, avatar: profiles.get(d.data().requesterUid as string)?.avatar, expiresAt: iso(d.data().expiresAt) }))
      .filter((r) => r.displayName !== undefined),
    outgoing: outgoing
      .map((d) => ({ requestId: d.id, displayName: profiles.get(d.data().inviterUid as string)?.name, avatar: profiles.get(d.data().inviterUid as string)?.avatar, expiresAt: iso(d.data().expiresAt) }))
      .filter((r) => r.displayName !== undefined),
  };
}

/** 当事者だけが解除できる。共有カードの権限は、読み取り時にフレンド状態を確認して失効させる（全件走査しない）。 */
export async function removeFriend(uid: string, friendshipId: string): Promise<void> {
  const ref = friendships().doc(friendshipId);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data() as DocumentData | undefined;
    if (!data || !(data.members as string[]).includes(uid) || data.status !== "active") throw new ApiError(404, "not_found");
    tx.update(ref, { status: "removed", removedAt: Timestamp.fromDate(now()) });
  });
}

/** ブロック：関係と申請を終わらせ、双方向で、再申請・新規共有を防ぐ。相手には通知しない。 */
export async function blockUser(uid: string, targetUid: string): Promise<void> {
  await loadActiveUser(uid);
  if (targetUid === uid || !targetUid || targetUid.length > 128) throw new ApiError(400, "invalid_target");
  const key = pairKey(uid, targetUid);
  await db().runTransaction(async (tx) => {
    const friendship = await tx.get(friendships().doc(key));
    const request = await tx.get(friendRequests().doc(key));
    tx.set(blockRef(uid, targetUid), { blockerUid: uid, blockedUid: targetUid, createdAt: Timestamp.fromDate(now()) });
    if (friendship.exists && friendship.data()?.status === "active") {
      tx.update(friendships().doc(key), { status: "removed", removedAt: Timestamp.fromDate(now()) });
    }
    if (request.exists && isPendingValid(request.data() as DocumentData)) {
      tx.update(friendRequests().doc(key), { status: "cancelled", decidedAt: Timestamp.fromDate(now()) });
    }
  });
}

/** ブロック解除。自動ではフレンドに戻さない。 */
export async function unblockUser(uid: string, targetUid: string): Promise<void> {
  await blockRef(uid, targetUid).delete();
}
