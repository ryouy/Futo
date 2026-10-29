import { type DocumentReference, type Transaction } from "firebase-admin/firestore";
import { now, dayKey } from "./clock";
import { db } from "./firebase";
import { ApiError } from "./http";

/** UID別・種類別の日次上限。作成と同じトランザクションの中で数えるので、同時に押されても超えない。 */
export interface DailyCounter {
  ref: DocumentReference;
  used: number;
}

export async function readDaily(tx: Transaction, uid: string, kind: string): Promise<DailyCounter> {
  const day = dayKey(now());
  const ref = db().collection("usageLimits").doc(`${uid}_${day}_${kind}`);
  const snap = await tx.get(ref);
  return { ref, used: snap.exists ? (snap.data()?.count as number) : 0 };
}

export function consumeDaily(tx: Transaction, counter: DailyCounter, uid: string, kind: string, max: number): void {
  if (counter.used >= max) throw new ApiError(429, "daily_limit");
  tx.set(counter.ref, { uid, kind, day: dayKey(now()), count: counter.used + 1 });
}
