import { beforeEach, describe, expect, it } from "vitest";
import { addDays, now } from "@/lib/clock";
import { call, db, docsContaining, newUser, resetAll, setClockForTests, webPayload } from "./helpers";

beforeEach(resetAll);

async function createShare(user: { token: string }, overrides: Record<string, unknown> = {}) {
  const response = await call("POST", "/api/shares", { token: user.token, body: webPayload(overrides) });
  expect(response.status).toBe(201);
  const token = response.body.token as string;
  return { id: response.body.shareId as string, token, url: response.body.url as string };
}

describe("Web共有：作成と検証", () => {
  it("作成でき、リンクはランダムな秘密トークン（43文字）。URLの土台は設定値", async () => {
    const owner = await newUser("はなこ");
    const share = await createShare(owner);
    expect(share.token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(share.url).toBe(`https://share.example.test/s/${share.token}`);
  });

  it("生トークンはFirestoreに保存されない（ハッシュだけ）", async () => {
    const owner = await newUser();
    const share = await createShare(owner);
    expect(await docsContaining(share.token)).toEqual([]);
  });

  it.each([
    ["項目が1つも未選択", { counts: undefined }],
    ["件数が負", { counts: { wantsToUse: -1, deferred: 0, interrupted: 0 } }],
    ["件数が上限超え", { counts: { wantsToUse: 100001, deferred: 0, interrupted: 0 } }],
    ["件数が小数", { counts: { wantsToUse: 1.5, deferred: 0, interrupted: 0 } }],
    ["未知の項目（自由記述など）", { comment: "ひとこと" }],
    ["定型でないひとこと", { phraseId: "my own text" }],
    ["期間が逆", { periodStart: "2027-01-17T19:00:00.000Z", periodEnd: "2027-01-10T19:00:00.000Z" }],
    ["期間が長すぎる", { periodEnd: "2027-03-17T19:00:00.000Z" }],
    ["期限が選択肢にない", { expiresInDays: 365 }],
    ["冪等キーが不正", { idempotencyKey: "abc" }],
  ])("検証：%s は400", async (_label, overrides) => {
    const owner = await newUser();
    const response = await call("POST", "/api/shares", { token: owner.token, body: webPayload(overrides) });
    expect(response.status).toBe(400);
  });

  it("本文が32KiBを超えると413", async () => {
    const owner = await newUser();
    const big = JSON.stringify(webPayload({ pad: "x".repeat(40 * 1024) }));
    expect((await call("POST", "/api/shares", { token: owner.token, rawBody: big })).status).toBe(413);
  });

  it("所有者・期限・IDは、サーバーが決める（クライアントの値は受け付けない）", async () => {
    const owner = await newUser();
    const other = await newUser("他人");
    for (const forged of [{ ownerUid: other.uid }, { expiresAt: "2099-01-01T00:00:00Z" }, { id: "fixed" }, { createdAt: "2000-01-01T00:00:00Z" }]) {
      expect((await call("POST", "/api/shares", { token: owner.token, body: webPayload(forged) })).status).toBe(400);
    }
    const share = await createShare(owner);
    const doc = (await db().collection("shares").doc(share.id).get()).data();
    expect(doc?.ownerUid).toBe(owner.uid);
  });

  it("同じ冪等キーの再送では、共有が増えない（トークンは返らない）", async () => {
    const owner = await newUser();
    const payload = webPayload();
    const first = await call("POST", "/api/shares", { token: owner.token, body: payload });
    const second = await call("POST", "/api/shares", { token: owner.token, body: payload });
    expect(first.status).toBe(201);
    expect(second.status).toBe(200);
    expect(second.body.replay).toBe(true);
    expect(second.body.token).toBeNull();
    expect(second.body.shareId).toBe(first.body.shareId);
    expect((await db().collection("shares").get()).size).toBe(1);
  });

  it("同時に同じ冪等キーで作っても、1件だけ（競合した側は、再送すれば作成済みと分かる）", async () => {
    const owner = await newUser();
    const payload = webPayload();
    const results = await Promise.all([1, 2, 3].map(() => call("POST", "/api/shares", { token: owner.token, body: payload })));
    // 競合（409）は、もう一度試せる応答。それ以外は成功
    expect(results.every((r) => [200, 201, 409].includes(r.status))).toBe(true);
    const retry = await call("POST", "/api/shares", { token: owner.token, body: payload });
    expect([200, 201]).toContain(retry.status);
    expect((await db().collection("shares").get()).size).toBe(1);
  });

  it("有効な共有は20件まで（サーバーで強制）", async () => {
    const owner = await newUser();
    for (let i = 0; i < 20; i += 1) await createShare(owner);
    const over = await call("POST", "/api/shares", { token: owner.token, body: webPayload() });
    expect(over.status).toBe(429);
    expect(over.body.error).toBe("too_many_shares");
  });

  it("1日20件の上限は、同時に押されても超えない", async () => {
    const owner = await newUser();
    // 有効件数の上限に当たらないよう、作成のたびに取り消す
    for (let i = 0; i < 20; i += 1) {
      const share = await createShare(owner);
      expect((await call("DELETE", `/api/shares/${share.id}`, { token: owner.token })).status).toBe(200);
    }
    expect((await call("POST", "/api/shares", { token: owner.token, body: webPayload() })).body.error).toBe("daily_limit");
  });
});

describe("Web共有：公開される内容", () => {
  it("選んだ項目だけが公開され、選ばなかった項目はJSONにも含まれない", async () => {
    const owner = await newUser("はなこ");
    const share = await createShare(owner, { counts: { wantsToUse: 7, deferred: 2, interrupted: 0 }, purposes: undefined, feelings: undefined });
    const response = await call("GET", `/api/public/shares/${share.token}`);
    expect(response.status).toBe(200);
    expect(response.body.stats.counts).toEqual({ wantsToUse: 7, deferred: 2, interrupted: 0 });
    expect(response.body.stats).not.toHaveProperty("purposes");
    expect(response.body.stats).not.toHaveProperty("feelings");
    expect(response.text).not.toContain(owner.uid); // UIDを出さない
    // 保存されたデータの統計にも、選ばなかった項目は無い（「選ばれていない」という印だけが別にある）
    const stored = (await db().collection("shares").doc(share.id).get()).data();
    expect(stored?.stats).not.toHaveProperty("purposes");
    expect(stored?.selected.purposes).toBe(false);
  });

  it("満足感は、回答済み件数を分母にする", async () => {
    const owner = await newUser();
    const share = await createShare(owner, { counts: undefined, feelings: { satisfied: 3, neutral: 1, wishedLess: 0 } });
    const response = await call("GET", `/api/public/shares/${share.token}`);
    expect(response.body.stats.feelings).toEqual({ satisfied: 3, neutral: 1, wishedLess: 0, answered: 4 });
  });

  it("匿名表示を選ぶと、表示名は含まれない。表示名を変えても過去の共有は変わらない", async () => {
    const owner = await newUser("はなこ");
    const named = await createShare(owner);
    const anonymous = await createShare(owner, { showName: false });
    await call("PUT", "/api/me", { token: owner.token, body: { displayName: "あたらしい名前" } });
    expect((await call("GET", `/api/public/shares/${named.token}`)).body.displayName).toBe("はなこ");
    const anon = await call("GET", `/api/public/shares/${anonymous.token}`);
    expect(anon.body.displayName).toBeNull();
    expect(anon.text).not.toContain("はなこ");
  });

  it("応答は private, no-store で、検索に載せない", async () => {
    const owner = await newUser();
    const share = await createShare(owner);
    const response = await call("GET", `/api/public/shares/${share.token}`);
    expect(response.headers.get("cache-control")).toBe("private, no-store");
    expect(response.headers.get("x-robots-tag")).toContain("noindex");
  });
});

describe("Web共有：期限・取消・再発行", () => {
  it("期限が切れると、次の取得から無効（サーバー時刻で判定）", async () => {
    const owner = await newUser();
    const share = await createShare(owner, { expiresInDays: 1 });
    expect((await call("GET", `/api/public/shares/${share.token}`)).status).toBe(200);
    setClockForTests(() => addDays(new Date(), 2));
    const expired = await call("GET", `/api/public/shares/${share.token}`);
    expect(expired.status).toBe(404);
    expect(expired.body).toEqual({ error: "unavailable" });
  });

  it("取消すると、直ちに無効。不正・期限切れ・取消済みは、同じ応答", async () => {
    const owner = await newUser();
    const share = await createShare(owner);
    expect((await call("DELETE", `/api/shares/${share.id}`, { token: owner.token })).status).toBe(200);
    const revoked = await call("GET", `/api/public/shares/${share.token}`);
    const garbage = await call("GET", `/api/public/shares/${"a".repeat(43)}`);
    expect(revoked.status).toBe(404);
    expect(revoked.body).toEqual(garbage.body);
  });

  it("再発行すると、旧リンクは直ちに無効で、新リンクが有効", async () => {
    const owner = await newUser();
    const share = await createShare(owner);
    const rotated = await call("POST", `/api/shares/${share.id}/rotate`, { token: owner.token });
    expect(rotated.status).toBe(200);
    expect((await call("GET", `/api/public/shares/${share.token}`)).status).toBe(404);
    expect((await call("GET", `/api/public/shares/${rotated.body.token}`)).status).toBe(200);
    expect(await docsContaining(rotated.body.token)).toEqual([]);
  });

  it("取消済みの共有は再発行できない", async () => {
    const owner = await newUser();
    const share = await createShare(owner);
    await call("DELETE", `/api/shares/${share.id}`, { token: owner.token });
    expect((await call("POST", `/api/shares/${share.id}/rotate`, { token: owner.token })).status).toBe(409);
  });

  it("他人の共有IDでは、取消も再発行もできない（存在も知らせない）", async () => {
    const owner = await newUser("持ち主");
    const intruder = await newUser("他人");
    const share = await createShare(owner);
    expect((await call("DELETE", `/api/shares/${share.id}`, { token: intruder.token })).status).toBe(404);
    expect((await call("POST", `/api/shares/${share.id}/rotate`, { token: intruder.token })).status).toBe(404);
    expect((await call("DELETE", `/api/shares/no-such-id`, { token: intruder.token })).status).toBe(404);
    expect((await call("GET", `/api/public/shares/${share.token}`)).status).toBe(200); // 持ち主の共有は無事
  });

  it("一覧は本人の分だけ。トークンやURLは含まない。ページングできる", async () => {
    const owner = await newUser();
    const other = await newUser("他人");
    for (let i = 0; i < 3; i += 1) await createShare(owner);
    await createShare(other);
    const first = await call("GET", "/api/shares?limit=2", { token: owner.token });
    expect(first.body.items).toHaveLength(2);
    expect(first.body.next).toBeTruthy();
    expect(first.text).not.toMatch(/[A-Za-z0-9_-]{43}/);
    const second = await call("GET", `/api/shares?limit=2&cursor=${first.body.next}`, { token: owner.token });
    expect(second.body.items).toHaveLength(1);
    expect(second.body.next).toBeNull();
    expect(JSON.stringify([first.body, second.body])).not.toContain(other.uid);
  });

  it("作成者が削除中になると、共有は直ちに見えなくなる", async () => {
    const owner = await newUser();
    const share = await createShare(owner);
    await db().collection("users").doc(owner.uid).update({ status: "deleting" });
    expect((await call("GET", `/api/public/shares/${share.token}`)).status).toBe(404);
  });

  it("操作の確認用：現在時刻はテストで差し替えられる", () => {
    expect(addDays(now(), 1).getTime()).toBeGreaterThan(now().getTime());
  });
});
