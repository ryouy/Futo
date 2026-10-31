import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { avatarSchema, displayNameSchema, type Avatar } from "./schema";

export interface UserDoc {
  displayName: string;
  avatar?: Avatar;
  status: "active" | "deleting";
}

export const userRef = (uid: string) => db().collection("users").doc(uid);

export function parseDisplayName(input: unknown): string {
  const parsed = displayNameSchema.safeParse(input);
  if (!parsed.success) throw new ApiError(400, "invalid_display_name");
  return parsed.data;
}

/** プロフィールの作成・更新。表示名は、アプリが初回ログイン時にGoogleの名前から作った初期値、または本人が変えた名前。メール・写真は受け取らない（写真はアプリ内の表示だけ）。 */
export function parseAvatar(input: unknown): Avatar | undefined {
  if (input === undefined) return undefined;
  const parsed = avatarSchema.safeParse(input);
  if (!parsed.success) throw new ApiError(400, "invalid_avatar");
  return parsed.data;
}

export async function putMe(uid: string, displayName: string, avatar?: Avatar) {
  const ref = userRef(uid);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.data()?.status === "deleting") throw new ApiError(403, "account_deleting");
    if (snap.exists) {
      tx.update(ref, { displayName, ...(avatar ? { avatar } : {}), updatedAt: Timestamp.fromDate(now()) });
    } else {
      tx.set(ref, { displayName, ...(avatar ? { avatar } : {}), status: "active", createdAt: Timestamp.fromDate(now()), updatedAt: Timestamp.fromDate(now()) });
    }
  });
  return { uid, displayName, ...(avatar ? { avatar } : {}) };
}

export async function getMe(uid: string) {
  const snap = await userRef(uid).get();
  if (!snap.exists) throw new ApiError(404, "profile_missing");
  const data = snap.data() as UserDoc;
  return { uid, displayName: data.displayName, status: data.status, ...(data.avatar ? { avatar: data.avatar } : {}) };
}

/** 共有・フレンド操作の前提：プロフィールがあり、削除中でない。 */
export async function loadActiveUser(uid: string): Promise<UserDoc> {
  const snap = await userRef(uid).get();
  if (!snap.exists) throw new ApiError(403, "profile_required");
  const data = snap.data() as UserDoc;
  if (data.status === "deleting") throw new ApiError(403, "account_deleting");
  return data;
}

/** UID→表示名とアイコン。削除中・不在のユーザーは含めない。 */
export async function activeProfiles(uids: string[]): Promise<Map<string, { name: string; avatar?: Avatar }>> {
  const result = new Map<string, { name: string; avatar?: Avatar }>();
  const unique = [...new Set(uids)];
  if (unique.length === 0) return result;
  const snaps = await db().getAll(...unique.map(userRef));
  for (const snap of snaps) {
    const data = snap.data() as UserDoc | undefined;
    if (data && data.status === "active") result.set(snap.id, { name: data.displayName, ...(data.avatar ? { avatar: data.avatar } : {}) });
  }
  return result;
}

export const increment = (n: number) => FieldValue.increment(n);
