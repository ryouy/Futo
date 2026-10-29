import { beforeEach, describe, expect, it } from "vitest";
import { purgeUserData } from "@/lib/accountDeletion";
import { addHours } from "@/lib/clock";
import { adminAuth, call, db, friendPayload, newUser, resetAll, setClockForTests, webPayload, type TestUser } from "./helpers";

beforeEach(resetAll);

async function befriend(a: TestUser, b: TestUser) {
  const inv = await call("POST", "/api/invitations", { token: a.token });
  const req = await call("POST", "/api/friend-requests", { token: b.token, body: { token: inv.body.token } });
  await call("POST", `/api/friend-requests/${req.body.requestId}/accept`, { token: a.token });
}

describe("アカウント削除", () => {
  it("直近のサインインがないと、削除を始められない", async () => {
    const user = await newUser();
    setClockForTests(() => addHours(new Date(), 1)); // トークンのauth_timeから1時間後
    const response = await call("DELETE", "/api/me", { token: user.token });
    expect(response.status).toBe(401);
    expect(response.body.error).toBe("recent_login_required");
    expect((await db().collection("users").doc(user.uid).get()).data()?.status).toBe("active");
  });

  it("削除を始めた時点で、残りのデータがあっても、共有は誰にも読めなくなる", async () => {
    const owner = await newUser("持ち主");
    const share = await call("POST", "/api/shares", { token: owner.token, body: webPayload() });
    const invite = await call("POST", "/api/invitations", { token: owner.token });
    expect((await call("GET", `/api/public/shares/${share.body.token}`)).status).toBe(200);

    // 削除の本体を実行せず、状態だけを「削除中」にする（途中で止まった状況）
    const { beginAccountDeletion } = await import("@/lib/accountDeletion");
    await beginAccountDeletion(owner.uid, Math.floor(Date.now() / 1000));
    expect((await call("GET", `/api/public/shares/${share.body.token}`)).status).toBe(404);
    expect((await call("GET", `/api/public/invitations/${invite.body.token}`)).status).toBe(404);
    // 削除中のアカウントは、書き込み操作もできない
    expect((await call("POST", "/api/shares", { token: owner.token, body: webPayload() })).body.error).toBe("account_deleting");
    expect((await call("PUT", "/api/me", { token: owner.token, body: { displayName: "x" } })).status).toBe(403);
  });

  it("途中で失敗しても、再試行で続きから完了する。共有は復活しない。Authは最後に消える", async () => {
    const owner = await newUser("持ち主");
    const friend = await newUser("友だち");
    await befriend(owner, friend);
    const share = await call("POST", "/api/shares", { token: owner.token, body: webPayload() });
    await call("POST", "/api/friend-shares", { token: owner.token, body: friendPayload([friend.uid]) });
    await call("POST", "/api/invitations", { token: owner.token });
    await call("POST", "/api/reports", { token: owner.token, body: { targetType: "user", targetId: friend.uid, reason: "spam" } });
    await call("POST", `/api/blocks/${friend.uid}`, { token: owner.token });

    const { beginAccountDeletion } = await import("@/lib/accountDeletion");
    await beginAccountDeletion(owner.uid, Math.floor(Date.now() / 1000));
    // 友達関係の削除ステップで失敗させる → Authは残り、共有は読めないまま
    await expect(purgeUserData(owner.uid, { failAtStep: "friendships" })).rejects.toThrow("injected_failure_friendships");
    expect((await db().collection("shares").get()).size).toBe(0); // それより前のステップは済んでいる
    expect((await adminAuth().getUser(owner.uid)).uid).toBe(owner.uid);
    expect((await call("GET", `/api/public/shares/${share.body.token}`)).status).toBe(404);

    // 再試行（同じAPIをもう一度呼ぶ）
    const retry = await call("DELETE", "/api/me", { token: owner.token });
    expect(retry.status).toBe(200);
    expect(retry.body.status).toBe("deleted");

    for (const name of ["shares", "shareTokens", "invitations", "invitationTokens", "friendRequests", "friendships", "friendShares", "blocks"]) {
      expect((await db().collection(name).get()).size, name).toBe(0);
    }
    expect((await db().collection("users").doc(owner.uid).get()).exists).toBe(false);
    await expect(adminAuth().getUser(owner.uid)).rejects.toMatchObject({ code: "auth/user-not-found" });
    expect((await call("GET", `/api/public/shares/${share.body.token}`)).status).toBe(404);
    // 友達のアカウントとデータは、そのまま
    expect((await call("GET", "/api/me", { token: friend.token })).status).toBe(200);
  });

  it("通報は、運営の確認のため残るが、通報者のUIDは匿名化される", async () => {
    const owner = await newUser();
    const other = await newUser("他人");
    await call("POST", "/api/reports", { token: owner.token, body: { targetType: "user", targetId: other.uid, reason: "spam" } });
    expect((await call("DELETE", "/api/me", { token: owner.token })).body.status).toBe("deleted");
    const reports = await db().collection("reports").get();
    expect(reports.size).toBe(1);
    expect(JSON.stringify(reports.docs[0].data())).not.toContain(owner.uid);
    expect(reports.docs[0].data().reporterUid).toMatch(/^deleted:/);
  });

  it("受け取っていたフレンド共有からは、受信者として外れる", async () => {
    const owner = await newUser("持ち主");
    const friend = await newUser("友だち");
    await befriend(owner, friend);
    const created = await call("POST", "/api/friend-shares", { token: owner.token, body: friendPayload([friend.uid]) });
    await call("DELETE", "/api/me", { token: friend.token });
    const doc = (await db().collection("friendShares").doc(created.body.shareId).get()).data();
    expect(doc?.recipientUids).toEqual([]);
    expect(doc?.grants).toEqual({});
  });

  it("削除後は、同じトークンで何もできない", async () => {
    const user = await newUser();
    await call("DELETE", "/api/me", { token: user.token });
    expect((await call("GET", "/api/me", { token: user.token })).status).toBe(401);
  });
});
