import { beforeEach, describe, expect, it } from "vitest";
import { addDays, addHours } from "@/lib/clock";
import { pairKey } from "@/lib/tokens";
import { call, db, docsContaining, friendPayload, newUser, resetAll, setClockForTests, type TestUser } from "./helpers";

beforeEach(resetAll);

async function invite(inviter: TestUser) {
  const response = await call("POST", "/api/invitations", { token: inviter.token });
  expect(response.status).toBe(201);
  return response.body as { inviteId: string; token: string; code: string; url: string; expiresAt: string };
}

async function request(requester: TestUser, invitation: { token?: string; code?: string }) {
  return call("POST", "/api/friend-requests", { token: requester.token, body: invitation.token ? { token: invitation.token } : { code: invitation.code } });
}

async function makeFriends(a: TestUser, b: TestUser) {
  const invitation = await invite(a);
  const requested = await request(b, { token: invitation.token });
  expect(requested.status).toBe(201);
  const accepted = await call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: a.token });
  expect(accepted.status).toBe(200);
  return { friendshipId: accepted.body.friendshipId as string, generation: accepted.body.generation as number };
}

describe("招待", () => {
  it("招待は24時間有効。リンクとコードは別物で、コードは12文字の英数字", async () => {
    const alice = await newUser("アリス");
    const invitation = await invite(alice);
    expect(invitation.code).toMatch(/^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$/);
    expect(invitation.url).toBe(`https://share.example.test/i/${invitation.token}`);
    const hours = (Date.parse(invitation.expiresAt) - Date.now()) / 3_600_000;
    expect(hours).toBeGreaterThan(23.9);
    expect(hours).toBeLessThanOrEqual(24);
  });

  it("招待の生トークン・コードはFirestoreに保存されない", async () => {
    const alice = await newUser();
    const invitation = await invite(alice);
    expect(await docsContaining(invitation.token)).toEqual([]);
    expect(await docsContaining(invitation.code)).toEqual([]);
  });

  it("統計共有のリンクでは、フレンドにならない（別トークン・別データ）", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const share = await call("POST", "/api/shares", { token: alice.token, body: (await import("./helpers")).webPayload() });
    expect((await call("GET", `/api/public/invitations/${share.body.token}`)).status).toBe(404);
    expect((await request(bob, { token: share.body.token })).status).toBe(404);
  });

  it("招待ページ用のGETでは、申請も消費もされない（プレビューやスキャンで使用済みにならない）", async () => {
    const alice = await newUser("アリス");
    const invitation = await invite(alice);
    for (let i = 0; i < 3; i += 1) {
      const preview = await call("GET", `/api/public/invitations/${invitation.token}`);
      expect(preview.status).toBe(200);
      expect(preview.body.inviterName).toBe("アリス");
      expect(preview.text).not.toContain(alice.uid);
    }
    expect((await db().collection("invitations").doc(invitation.inviteId).get()).data()?.status).toBe("open");
    expect((await db().collection("friendRequests").get()).size).toBe(0);
  });

  it("招待者だけが取り消せる。取り消すと、リンクもコードも無効", async () => {
    const alice = await newUser();
    const mallory = await newUser("他人");
    const invitation = await invite(alice);
    expect((await call("DELETE", `/api/invitations/${invitation.inviteId}`, { token: mallory.token })).status).toBe(404);
    expect((await call("DELETE", `/api/invitations/${invitation.inviteId}`, { token: alice.token })).status).toBe(200);
    expect((await call("GET", `/api/public/invitations/${invitation.token}`)).status).toBe(404);
    expect((await request(mallory, { code: invitation.code })).status).toBe(404);
  });

  it("1日10件まで", async () => {
    const alice = await newUser();
    for (let i = 0; i < 10; i += 1) await invite(alice);
    expect((await call("POST", "/api/invitations", { token: alice.token })).body.error).toBe("daily_limit");
  });
});

describe("フレンド申請と承認", () => {
  it("申請前・申請中は、限定共有を見られない。承認の後で初めてフレンドになる", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    // 申請前：フレンドではないので、共有の受信者に選べない
    expect((await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) })).status).toBe(403);

    const invitation = await invite(alice);
    const requested = await request(bob, { token: invitation.token });
    expect(requested.status).toBe(201);
    // 申請中：まだフレンドではない
    expect((await call("GET", "/api/friends", { token: bob.token })).body.friends).toEqual([]);
    expect((await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) })).status).toBe(403);
    // 承認前は、招待者の一覧にだけ申請が出る
    const incoming = (await call("GET", "/api/friends", { token: alice.token })).body.incoming;
    expect(incoming).toHaveLength(1);
    expect(incoming[0].displayName).toBe("ボブ");

    await call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: alice.token });
    expect((await call("GET", "/api/friends", { token: bob.token })).body.friends).toHaveLength(1);
    expect((await call("GET", "/api/friends", { token: alice.token })).body.friends[0].displayName).toBe("ボブ");
  });

  it("コード入力でも申請できる（小文字・区切りも許容）", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const invitation = await invite(alice);
    const spaced = `${invitation.code.slice(0, 4)}-${invitation.code.slice(4, 8)} ${invitation.code.slice(8)}`.toLowerCase();
    expect((await request(bob, { code: spaced })).status).toBe(201);
  });

  it("招待は成功申請1件限り（2人目の申請は拒否）", async () => {
    const alice = await newUser();
    const bob = await newUser("ボブ");
    const carol = await newUser("キャロル");
    const invitation = await invite(alice);
    expect((await request(bob, { token: invitation.token })).status).toBe(201);
    expect((await request(carol, { token: invitation.token })).status).toBe(410);
  });

  it("同じ招待に、同時に2人が申請しても、1件だけ通る", async () => {
    const alice = await newUser();
    const bob = await newUser("ボブ");
    const carol = await newUser("キャロル");
    const invitation = await invite(alice);
    const results = await Promise.all([request(bob, { token: invitation.token }), request(carol, { token: invitation.token })]);
    const statuses = results.map((r) => r.status);
    // 成立するのは1件だけ。負けた側は「使用済み」か、同時操作の競合（もう一度試せる）として拒否される
    expect(statuses.filter((s) => s === 201)).toHaveLength(1);
    expect(statuses.filter((s) => s === 410 || s === 409)).toHaveLength(1);
    expect((await db().collection("friendRequests").get()).size).toBe(1);
    expect((await db().collection("invitations").doc(invitation.inviteId).get()).data()?.status).toBe("consumed");
  });

  it("期限切れ・自己招待・存在しない招待を拒否する", async () => {
    const alice = await newUser();
    const bob = await newUser("ボブ");
    const own = await invite(alice);
    expect((await request(alice, { token: own.token })).status).toBe(400);
    const expiring = await invite(alice);
    setClockForTests(() => addHours(new Date(), 25));
    expect((await request(bob, { token: expiring.token })).status).toBe(410);
    expect((await call("GET", `/api/public/invitations/${expiring.token}`)).status).toBe(404);
    setClockForTests(null);
    expect((await request(bob, { token: "a".repeat(43) })).status).toBe(404);
  });

  it("既にフレンドの相手からの新しい招待は、申請できない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    await makeFriends(alice, bob);
    const again = await invite(alice);
    expect((await request(bob, { token: again.token })).body.error).toBe("already_friends");
  });

  it("承認できるのは招待者だけ。申請者本人や第三者の承認は、存在しないのと同じ応答", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const mallory = await newUser("悪意");
    const invitation = await invite(alice);
    const requested = await request(bob, { token: invitation.token });
    const id = requested.body.requestId;
    expect((await call("POST", `/api/friend-requests/${id}/accept`, { token: bob.token })).status).toBe(404);
    expect((await call("POST", `/api/friend-requests/${id}/accept`, { token: mallory.token })).status).toBe(404);
    expect((await call("POST", `/api/friend-requests/${id}/decline`, { token: mallory.token })).status).toBe(404);
    expect((await call("DELETE", `/api/friend-requests/${id}`, { token: mallory.token })).status).toBe(404);
    expect((await db().collection("friendships").get()).size).toBe(0);
  });

  it("転送された第三者の申請でも自動承認しない。見送ると、再招待は新しい招待が必要", async () => {
    const alice = await newUser("アリス");
    const stranger = await newUser("見知らぬ人");
    const invitation = await invite(alice);
    const requested = await request(stranger, { token: invitation.token });
    expect((await call("GET", "/api/friends", { token: stranger.token })).body.friends).toEqual([]);
    expect((await call("POST", `/api/friend-requests/${requested.body.requestId}/decline`, { token: alice.token })).status).toBe(200);
    expect((await call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: alice.token })).status).toBe(409);
    expect((await request(stranger, { token: invitation.token })).status).toBe(410); // 同じ招待は使えない
    expect((await request(stranger, { token: (await invite(alice)).token })).status).toBe(201); // 新しい招待なら申請できる
  });

  it("申請者は取り消せる。取り消した申請は承認できない", async () => {
    const alice = await newUser();
    const bob = await newUser("ボブ");
    const requested = await request(bob, { token: (await invite(alice)).token });
    expect((await call("DELETE", `/api/friend-requests/${requested.body.requestId}`, { token: bob.token })).status).toBe(200);
    expect((await call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: alice.token })).status).toBe(409);
  });

  it("申請は7日で失効（サーバー時刻で判定）", async () => {
    const alice = await newUser();
    const bob = await newUser("ボブ");
    const requested = await request(bob, { token: (await invite(alice)).token });
    setClockForTests(() => addDays(new Date(), 8));
    expect((await call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: alice.token })).status).toBe(409);
    expect((await call("GET", "/api/friends", { token: alice.token })).body.incoming).toEqual([]);
  });

  it("同時承認・二重押しでも、フレンド関係は1つだけ", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const requested = await request(bob, { token: (await invite(alice)).token });
    const results = await Promise.all([1, 2, 3].map(() => call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: alice.token })));
    expect(results.filter((r) => r.status === 200)).toHaveLength(1);
    const docs = await db().collection("friendships").get();
    expect(docs.size).toBe(1);
    expect(docs.docs[0].id).toBe(pairKey(alice.uid, bob.uid));
  });

  it("逆方向の同時申請でも、申請は1件だけ（ペアキーで一意）", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const fromAlice = await invite(alice);
    const fromBob = await invite(bob);
    const results = await Promise.all([request(bob, { token: fromAlice.token }), request(alice, { token: fromBob.token })]);
    expect(results.filter((r) => r.status === 201)).toHaveLength(1);
    expect((await db().collection("friendRequests").get()).size).toBe(1);
  });

  it("承認の同時実行と、申請者の取消が競合しても、矛盾した状態にならない", async () => {
    const alice = await newUser();
    const bob = await newUser("ボブ");
    const requested = await request(bob, { token: (await invite(alice)).token });
    const [accept, cancel] = await Promise.all([
      call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: alice.token }),
      call("DELETE", `/api/friend-requests/${requested.body.requestId}`, { token: bob.token }),
    ]);
    const friends = (await call("GET", "/api/friends", { token: alice.token })).body.friends;
    // どちらか一方だけが成立し、承認が成立したときだけフレンドになる
    expect([accept.status, cancel.status].filter((s) => s === 200)).toHaveLength(1);
    expect(friends).toHaveLength(accept.status === 200 ? 1 : 0);
  });

  it("コードの総当たりを制限する（失敗が続くと429）", async () => {
    const bob = await newUser("ボブ");
    let last = 0;
    for (let i = 0; i < 12; i += 1) last = (await request(bob, { code: "ABCDEFGHJKMN" })).status;
    expect(last).toBe(429);
  });
});

describe("解除・ブロック・フレンド限定共有", () => {
  it("フレンドだけが受信者になれる。選ばれた相手だけが読める。無関係の人は読めない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const carol = await newUser("キャロル"); // フレンドだが、受信者に選ばない
    const outsider = await newUser("無関係");
    await makeFriends(alice, bob);
    await makeFriends(alice, carol);
    const created = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    expect(created.status).toBe(201);
    const id = created.body.shareId;
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(200);
    expect((await call("GET", `/api/friend-shares/${id}`, { token: carol.token })).status).toBe(404);
    expect((await call("GET", `/api/friend-shares/${id}`, { token: outsider.token })).status).toBe(404);
    expect((await call("GET", `/api/friend-shares/${id}`)).status).toBe(401);
    expect((await call("GET", "/api/friend-shares", { token: bob.token })).body.items).toHaveLength(1);
    expect((await call("GET", "/api/friend-shares", { token: carol.token })).body.items).toHaveLength(0);
  });

  it("新しいフレンドに、過去のカードを自動公開しない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const carol = await newUser("キャロル");
    await makeFriends(alice, bob);
    const created = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    await makeFriends(alice, carol); // あとからフレンドになる
    expect((await call("GET", `/api/friend-shares/${created.body.shareId}`, { token: carol.token })).status).toBe(404);
    expect((await call("GET", "/api/friend-shares", { token: carol.token })).body.items).toEqual([]);
  });

  it("解除すると、既存のカードは新規取得できない。再承認しても、古い権限は復活しない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const { friendshipId } = await makeFriends(alice, bob);
    const created = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    const id = created.body.shareId;
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(200);

    expect((await call("DELETE", `/api/friends/${friendshipId}`, { token: alice.token })).status).toBe(200);
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(404);
    expect((await call("GET", "/api/friend-shares", { token: bob.token })).body.items).toEqual([]);

    const again = await makeFriends(alice, bob);
    expect(again.generation).toBe(2); // 関係の世代が進む
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(404); // 古い権限は復活しない
    // 新しい共有は、新しい世代で読める
    const fresh = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    expect((await call("GET", `/api/friend-shares/${fresh.body.shareId}`, { token: bob.token })).status).toBe(200);
  });

  it("当事者でない人は、解除できない", async () => {
    const alice = await newUser();
    const bob = await newUser("ボブ");
    const mallory = await newUser("悪意");
    const { friendshipId } = await makeFriends(alice, bob);
    expect((await call("DELETE", `/api/friends/${friendshipId}`, { token: mallory.token })).status).toBe(404);
    expect((await call("GET", "/api/friends", { token: alice.token })).body.friends).toHaveLength(1);
  });

  it("ブロックすると、関係が終わり、双方向で、再申請・新規共有ができない。相手には知らせない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    await makeFriends(alice, bob);
    const created = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    expect((await call("POST", `/api/blocks/${bob.uid}`, { token: alice.token })).status).toBe(200);

    expect((await call("GET", "/api/friends", { token: bob.token })).body.friends).toEqual([]);
    expect((await call("GET", `/api/friend-shares/${created.body.shareId}`, { token: bob.token })).status).toBe(404);
    // 双方向：ブロックされた側から申請しても、招待者側から招待を使っても、成立しない
    const fromAlice = await invite(alice);
    expect((await request(bob, { token: fromAlice.token })).status).toBe(403);
    const fromBob = await invite(bob);
    expect((await request(alice, { token: fromBob.token })).status).toBe(403);
    // ブロックされた側の画面には、ブロックの事実が出ない
    expect(JSON.stringify((await call("GET", "/api/friends", { token: bob.token })).body)).not.toContain("block");
    // ブロック解除しても、自動ではフレンドに戻らない
    await call("DELETE", `/api/blocks/${bob.uid}`, { token: alice.token });
    expect((await call("GET", "/api/friends", { token: alice.token })).body.friends).toEqual([]);
  });

  it("ブロック中の申請は取り消され、承認できない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const requested = await request(bob, { token: (await invite(alice)).token });
    await call("POST", `/api/blocks/${bob.uid}`, { token: alice.token });
    expect((await call("POST", `/api/friend-requests/${requested.body.requestId}/accept`, { token: alice.token })).status).toBe(409);
  });

  it("フレンドでない人・ブロック中の人を、受信者にできない。自分自身も不可", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const stranger = await newUser("他人");
    await makeFriends(alice, bob);
    expect((await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid, stranger.uid]) })).status).toBe(403);
    expect((await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([alice.uid]) })).status).toBe(400);
    await call("POST", `/api/blocks/${bob.uid}`, { token: alice.token });
    expect((await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) })).status).toBe(403);
  });

  it("期限は30日。取消でき、受信者の側から作成者のカードを消せない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    await makeFriends(alice, bob);
    const created = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    const id = created.body.shareId;
    const days = (Date.parse(created.body.expiresAt) - Date.now()) / 86_400_000;
    expect(days).toBeGreaterThan(29.9);
    expect((await call("DELETE", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(404);
    setClockForTests(() => addDays(new Date(), 31));
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(404);
    setClockForTests(null);
    expect((await call("DELETE", `/api/friend-shares/${id}`, { token: alice.token })).status).toBe(200);
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(404);
  });

  it("作成の再送で、フレンド共有が増えない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    await makeFriends(alice, bob);
    const payload = friendPayload([bob.uid]);
    await call("POST", "/api/friend-shares", { token: alice.token, body: payload });
    const second = await call("POST", "/api/friend-shares", { token: alice.token, body: payload });
    expect(second.body.replay).toBe(true);
    expect((await db().collection("friendShares").get()).size).toBe(1);
  });
});

describe("継続共有（更新）と全期間", () => {
  const stats = (overrides: Record<string, unknown> = {}) => {
    const { recipientUids: _r, idempotencyKey: _k, ...rest } = friendPayload([]);
    return { ...rest, ...overrides };
  };

  async function setup() {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    const carol = await newUser("キャロル");
    await makeFriends(alice, bob);
    await makeFriends(alice, carol);
    const created = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    return { alice, bob, carol, id: created.body.shareId as string };
  }

  it("作成者は、統計を差し替えられる。期限は更新時点から30日に延び、受信者は変わらない", async () => {
    const { alice, bob, carol, id } = await setup();
    setClockForTests(() => addDays(new Date(), 10));
    const updated = await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: stats({ counts: { wantsToUse: 9, deferred: 8, interrupted: 7 }, purposes: { contact: 1, research: 2, break: 3, noReason: 4, unanswered: 0 } }) });
    expect(updated.status).toBe(200);
    const seen = await call("GET", `/api/friend-shares/${id}`, { token: bob.token });
    expect(seen.body.stats.counts).toEqual({ wantsToUse: 9, deferred: 8, interrupted: 7 });
    expect(seen.body.stats.purposes.break).toBe(3);
    expect(Date.parse(seen.body.expiresAt)).toBeGreaterThan(addDays(new Date(), 38).getTime());
    expect(Date.parse(seen.body.updatedAt)).toBeGreaterThan(Date.parse(seen.body.createdAt));
    expect((await call("GET", `/api/friend-shares/${id}`, { token: carol.token })).status).toBe(404); // 受信者は増えない
  });

  it("選ばなくなった項目は、更新後に消える（以前の値は残らない）", async () => {
    const { alice, bob, id } = await setup();
    await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: stats({ counts: undefined, feelings: { satisfied: 1, neutral: 0, wishedLess: 0 } }) });
    const seen = await call("GET", `/api/friend-shares/${id}`, { token: bob.token });
    expect(seen.body.stats.counts).toBeUndefined();
    expect(seen.body.stats.feelings.answered).toBe(1);
  });

  it("作成者以外・受信者・無関係の人・未ログインは、更新できない", async () => {
    const { bob, carol, id } = await setup();
    expect((await call("PUT", `/api/friend-shares/${id}`, { token: bob.token, body: stats() })).status).toBe(404);
    expect((await call("PUT", `/api/friend-shares/${id}`, { token: carol.token, body: stats() })).status).toBe(404);
    expect((await call("PUT", `/api/friend-shares/${id}`, { body: stats() })).status).toBe(401);
  });

  it("停止した共有・期限切れの共有は、更新で復活しない", async () => {
    const { alice, bob, id } = await setup();
    await call("DELETE", `/api/friend-shares/${id}`, { token: alice.token });
    expect((await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: stats() })).status).toBe(404);
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(404);

    const second = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid]) });
    setClockForTests(() => addDays(new Date(), 31));
    const lapsed = await call("PUT", `/api/friend-shares/${second.body.shareId}`, { token: alice.token, body: stats() });
    expect(lapsed.status).toBe(410);
    expect((await call("GET", `/api/friend-shares/${second.body.shareId}`, { token: bob.token })).status).toBe(404);
  });

  it("フレンドをやめた相手には、更新しても見えない", async () => {
    const { alice, bob, id } = await setup();
    const friends = await call("GET", "/api/friends", { token: alice.token });
    await call("DELETE", `/api/friends/${friends.body.friends.find((f: { uid: string }) => f.uid === bob.uid).friendshipId}`, { token: alice.token });
    await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: stats() });
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).status).toBe(404);
  });

  it("更新は1日48回まで（サーバーで強制）", async () => {
    const { alice, id } = await setup();
    for (let i = 0; i < 48; i++) {
      const r = await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: stats() });
      expect(r.status).toBe(200);
    }
    expect((await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: stats() })).status).toBe(429);
  }, 60_000);

  it("全期間は、最大10年まで。週は8日まで", async () => {
    const { alice, id } = await setup();
    const all = stats({ period: "all", periodStart: "2024-01-01T00:00:00.000Z", periodEnd: "2027-01-17T19:00:00.000Z", isPartial: false });
    expect((await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: all })).status).toBe(200);
    const tooLong = stats({ period: "all", periodStart: "2010-01-01T00:00:00.000Z", periodEnd: "2027-01-17T19:00:00.000Z" });
    expect((await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: tooLong })).status).toBe(400);
    const longWeek = stats({ period: "thisWeek", periodStart: "2026-12-01T00:00:00.000Z", periodEnd: "2027-01-17T19:00:00.000Z" });
    expect((await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: longWeek })).status).toBe(400);
  });

  it("Webリンクでも、全期間を共有できる。ページに全期間と表示される", async () => {
    const alice = await newUser("アリス");
    const created = await call("POST", "/api/shares", { token: alice.token, body: friendlessWeb() });
    expect(created.status).toBe(201);
    const page = await call("GET", `/api/public/shares/${created.body.token}`);
    expect(page.body.stats.period).toBe("all");
  });
});

function friendlessWeb() {
  return {
    period: "all", periodStart: "2025-01-01T00:00:00.000Z", periodEnd: "2027-01-17T19:00:00.000Z", timezone: "Asia/Tokyo", isPartial: false,
    showName: true, counts: { wantsToUse: 50, deferred: 30, interrupted: 10 }, expiresInDays: 7, idempotencyKey: crypto.randomUUID(),
  };
}

describe("自分自身の招待・一言（自由入力）", () => {
  it("自分の招待には、リンクでもコードでも申請できない。申請は作られない", async () => {
    const alice = await newUser("アリス");
    const invitation = await invite(alice);
    const byToken = await request(alice, { token: invitation.token });
    expect(byToken.status).toBe(400);
    expect(byToken.body.error).toBe("self_invite");
    const byCode = await request(alice, { code: invitation.code });
    expect(byCode.status).toBe(400);
    expect(byCode.body.error).toBe("self_invite");
    expect((await call("GET", "/api/friends", { token: alice.token })).body.outgoing).toEqual([]);
    expect((await call("GET", "/api/friends", { token: alice.token })).body.incoming).toEqual([]);
    // 招待は、本人が試したあとも、他の人が使える
    const bob = await newUser("ボブ");
    expect((await request(bob, { token: invitation.token })).status).toBe(201);
  });

  it("一言は、フレンドに届く。更新でも変えられ、空にすると消える", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    await makeFriends(alice, bob);
    const created = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid], { message: "  今週は少しがんばった！ " }) });
    expect(created.status).toBe(201);
    const id = created.body.shareId as string;
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).body.stats.message).toBe("今週は少しがんばった！");
    const { recipientUids: _r, idempotencyKey: _k, ...rest } = friendPayload([]);
    await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: { ...rest, message: "更新しました" } });
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).body.stats.message).toBe("更新しました");
    await call("PUT", `/api/friend-shares/${id}`, { token: alice.token, body: rest });
    expect((await call("GET", `/api/friend-shares/${id}`, { token: bob.token })).body.stats.message).toBeUndefined();
  });

  it("一言は、61文字以上・URL・制御文字・空白だけを拒否する", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    await makeFriends(alice, bob);
    for (const bad of ["あ".repeat(61), "見て https://evil.example/x", "www.example.com へ", "pay me at evil.com", "a\u0000b", "   "]) {
      const r = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid], { message: bad }) });
      expect(r.status, JSON.stringify(bad)).toBe(400);
    }
    const ok = await call("POST", "/api/friend-shares", { token: alice.token, body: friendPayload([bob.uid], { message: "あ".repeat(60) }) });
    expect(ok.status).toBe(201);
  });

  it("Webの公開リンクでも、一言（自由入力）は使える。URLや長すぎる文は拒否", async () => {
    const alice = await newUser("アリス");
    const ok = await call("POST", "/api/shares", { token: alice.token, body: webPayloadWithMessage() });
    expect(ok.status).toBe(201);
    const page = await call("GET", `/api/public/shares/${ok.body.token}`);
    expect(page.body.stats.message).toBe("こんにちは");
    for (const bad of ["https://example.com", "あ".repeat(61), "x\u0000y"]) {
      const r = await call("POST", "/api/shares", { token: alice.token, body: { ...webPayloadWithMessage(), idempotencyKey: crypto.randomUUID(), message: bad } });
      expect(r.status).toBe(400);
    }
  });
});

function webPayloadWithMessage() {
  return {
    period: "thisWeek", periodStart: "2027-01-10T19:00:00.000Z", periodEnd: "2027-01-17T19:00:00.000Z", timezone: "Asia/Tokyo", isPartial: true,
    showName: true, counts: { wantsToUse: 1, deferred: 1, interrupted: 0 }, expiresInDays: 7, idempotencyKey: crypto.randomUUID(), message: "こんにちは",
  };
}

describe("アプリ名の共有・招待ページのコード", () => {
  it("アプリ名は、選んだときだけ保存され、10件まで・40文字まで。制御文字は拒否", async () => {
    const alice = await newUser("アリス");
    const ok = await call("POST", "/api/shares", { token: alice.token, body: webPayloadApps([{ name: "動画アプリ", count: 7 }, { name: "SNS", count: 3 }]) });
    expect(ok.status).toBe(201);
    const page = await call("GET", `/api/public/shares/${ok.body.token}`);
    expect(page.body.stats.apps).toEqual([{ name: "動画アプリ", count: 7 }, { name: "SNS", count: 3 }]);
    for (const bad of [Array.from({ length: 11 }, (_, i) => ({ name: `A${i}`, count: 1 })), [{ name: "a".repeat(41), count: 1 }], [{ name: "x\u0000y", count: 1 }], [{ name: "ok", count: 1, extra: 1 }], []]) {
      expect((await call("POST", "/api/shares", { token: alice.token, body: webPayloadApps(bad as never) })).status).toBe(400);
    }
  });

  it("アプリ名だけを選んだ共有も作れる。何も選ばなければ作れない", async () => {
    const alice = await newUser("アリス");
    const onlyApps = { ...webPayloadApps([{ name: "動画", count: 2 }]), counts: undefined };
    expect((await call("POST", "/api/shares", { token: alice.token, body: onlyApps })).status).toBe(201);
    const nothing = { ...webPayloadApps([{ name: "動画", count: 2 }]), counts: undefined, apps: undefined, idempotencyKey: crypto.randomUUID() };
    expect((await call("POST", "/api/shares", { token: alice.token, body: nothing })).status).toBe(400);
  });

  it("招待ページには、リンクと同じ招待のコードを出せる。別の人には、コードは推測できない", async () => {
    const alice = await newUser("アリス");
    const created = await invite(alice);
    const info = await call("GET", `/api/public/invitations/${created.token}`);
    expect(info.status).toBe(200);
    expect(info.body.code).toBe(created.code);
    // そのコードで、申請もできる
    const bob = await newUser("ボブ");
    expect((await request(bob, { code: info.body.code })).status).toBe(201);
  });

  it("以前の方式で作られた招待（コードがトークンから導けない）では、コードを出さない", async () => {
    const alice = await newUser("アリス");
    const created = await invite(alice);
    const snap = await db().collection("invitations").doc(created.inviteId).get();
    await snap.ref.update({ codeHash: "0".repeat(64) });
    const info = await call("GET", `/api/public/invitations/${created.token}`);
    expect(info.status).toBe(200);
    expect(info.body.code).toBeNull();
  });
});

function webPayloadApps(apps: { name: string; count: number }[]) {
  return {
    period: "thisWeek", periodStart: "2027-01-10T19:00:00.000Z", periodEnd: "2027-01-17T19:00:00.000Z", timezone: "Asia/Tokyo", isPartial: true,
    showName: true, counts: { wantsToUse: 1, deferred: 1, interrupted: 0 }, apps, expiresInDays: 7, idempotencyKey: crypto.randomUUID(),
  };
}

describe("制限の管理の共有", () => {
  it("一時停止・終了の回数は、選んだときだけ保存される。それだけを選んだ共有も作れる", async () => {
    const alice = await newUser("アリス");
    const body = { ...webPayloadApps([{ name: "動画", count: 1 }]), apps: undefined, counts: undefined, restriction: { pauses: 3, ends: 1 } };
    const created = await call("POST", "/api/shares", { token: alice.token, body });
    expect(created.status).toBe(201);
    const page = await call("GET", `/api/public/shares/${created.body.token}`);
    expect(page.body.stats.restriction).toEqual({ pauses: 3, ends: 1 });
    const bad = { ...body, restriction: { pauses: -1, ends: 0 }, idempotencyKey: crypto.randomUUID() };
    expect((await call("POST", "/api/shares", { token: alice.token, body: bad })).status).toBe(400);
    const extra = { ...body, restriction: { pauses: 1, ends: 0, note: "x" }, idempotencyKey: crypto.randomUUID() };
    expect((await call("POST", "/api/shares", { token: alice.token, body: extra })).status).toBe(400);
  });
});
