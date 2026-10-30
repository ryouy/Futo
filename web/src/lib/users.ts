import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { now } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";
import { displayNameSchema } from "./schema";

export interface UserDoc {
  displayName: string;
  status: "active" | "deleting";
}

export const userRef = (uid: string) => db().collection("users").doc(uid);

export function parseDisplayName(input: unknown): string {
  const parsed = displayNameSchema.safeParse(input);
  if (!parsed.success) throw new ApiError(400, "invalid_display_name");
  return parsed.data;
}

/** プロフィールの作成・更新。表示名は、アプリが初回ログイン時にGoogleの名前から作った初期値、または本人が変えた名前。メール・写真は受け取らない。 */
export async function putMe(uid: string, displayName: string) {
  const ref = userRef(uid);
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists && snap.data()?.status === "deleting") throw new ApiError(403, "account_deleting");
    if (snap.exists) {
      tx.update(ref, { displayName, updatedAt: Timestamp.fromDate(now()) });
    } else {
      tx.set(ref, { displayName, status: "active", createdAt: Timestamp.fromDate(now()), updatedAt: Timestamp.fromDate(now()) });
    }
  });
  return { uid, displayName };
}

export async function getMe(uid: string) {
  const snap = await userRef(uid).get();
  if (!snap.exists) throw new ApiError(404, "profile_missing");
  const data = snap.data() as UserDoc;
  return { uid, displayName: data.displayName, status: data.status };
}

/** 共有・フレンド操作の前提：プロフィールがあり、削除中でない。 */
export async function loadActiveUser(uid: string): Promise<UserDoc> {
  const snap = await userRef(uid).get();
  if (!snap.exists) throw new ApiError(403, "profile_required");
  const data = snap.data() as UserDoc;
  if (data.status === "deleting") throw new ApiError(403, "account_deleting");
  return data;
}

/** UID→表示名。削除中・不在のユーザーは含めない。 */
export async function activeNames(uids: string[]): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  const unique = [...new Set(uids)];
  if (unique.length === 0) return result;
  const snaps = await db().getAll(...unique.map(userRef));
  for (const snap of snaps) {
    const data = snap.data() as UserDoc | undefined;
    if (data && data.status === "active") result.set(snap.id, data.displayName);
  }
  return result;
}

export const increment = (n: number) => FieldValue.increment(n);
