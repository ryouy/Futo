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

describe("通報", () => {
  it("定型の理由だけを受け付け、通報は誰からも読み取れない", async () => {
    const alice = await newUser("アリス");
    const bob = await newUser("ボブ");
    expect((await call("POST", "/api/reports", { token: alice.token, body: { targetType: "user", targetId: bob.uid, reason: "spam" } })).status).toBe(201);
    expect((await call("POST", "/api/reports", { token: alice.token, body: { targetType: "user", targetId: bob.uid, reason: "free text here" } })).status).toBe(400);
    expect((await call("POST", "/api/reports", { token: alice.token, body: { targetType: "user", targetId: bob.uid, reason: "spam", comment: "x" } })).status).toBe(400);
    expect((await call("GET", "/api/reports", { token: bob.token }).catch((e: Error) => ({ status: 0, error: e.message }))).status).toBe(0); // 読み取りのAPIが存在しない
  });

  it("匿名のWeb通報は、IPごとの持続する制限つき（1時間5件）", async () => {
    const alice = await newUser("アリス");
    const share = await call("POST", "/api/shares", { token: alice.token, body: (await import("./helpers")).webPayload() });
    const statuses: number[] = [];
    for (let i = 0; i < 7; i += 1) {
      statuses.push((await call("POST", "/api/public/reports", { body: { token: share.body.token, reason: "spam" }, ip: "198.51.100.7" })).status);
    }
    expect(statuses.slice(0, 5)).toEqual([201, 201, 201, 201, 201]);
    expect(statuses.slice(5)).toEqual([429, 429]);
    // 別のIPからは、まだ送れる
    expect((await call("POST", "/api/public/reports", { body: { token: share.body.token, reason: "spam" }, ip: "198.51.100.8" })).status).toBe(201);
  });
});
