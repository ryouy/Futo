/**
 * 期限切れデータの整理（手動実行）。Cloud Functions・TTLは使わない前提なので、必要なときに自分で実行する。
 *
 *   npm run cleanup:dry-run              件数だけ表示（何も消さない）
 *   npx tsx scripts/cleanup.ts --apply   実際に削除する
 *
 * 対象は、期限（expiresAt）が「猶予日数」より前に切れたドキュメントだけ。有効なデータには触れない。
 * 本番に対して実行するときは、FIREBASE_* の環境変数が必要（docs/PHASE4_SETUP.md）。
 */
import { Timestamp } from "firebase-admin/firestore";
import { db } from "../src/lib/firebase";

const COLLECTIONS = ["shares", "shareTokens", "friendShares", "invitations", "invitationTokens", "friendRequests", "operationKeys"];
const GRACE_DAYS = Number(process.env.CLEANUP_GRACE_DAYS ?? 30);

async function main() {
  const apply = process.argv.includes("--apply");
  const cutoff = Timestamp.fromMillis(Date.now() - GRACE_DAYS * 86_400_000);
  console.log(`${apply ? "削除します" : "ドライラン（削除しません）"}：${GRACE_DAYS}日以上前に期限が切れたデータ`);
  let total = 0;
  for (const name of COLLECTIONS) {
    let count = 0;
    for (;;) {
      const snap = await db().collection(name).where("expiresAt", "<", cutoff).limit(400).get();
      if (snap.empty) break;
      count += snap.size;
      if (!apply) break; // ドライランは、最初の1ページ分だけ数える（実際の件数は、これ以上のことがある）
      const batch = db().batch();
      snap.docs.forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
    }
    total += count;
    console.log(`  ${name}: ${count}${apply ? " 件を削除" : " 件（最大400件まで数えます）"}`);
  }
  console.log(`合計 ${total} 件`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
