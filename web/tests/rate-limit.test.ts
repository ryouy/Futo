import { beforeEach, describe, expect, it } from "vitest";
import { addHours } from "@/lib/clock";
import { call, db, newUser, resetAll, setClockForTests, webPayload } from "./helpers";

beforeEach(resetAll);

describe("匿名APIのレート制限（持続する制限）", () => {
  it("無効なトークンを試し続けると429。有効なリンクは、制限の対象にならない人からは見られる", async () => {
    const owner = await newUser();
    const share = await call("POST", "/api/shares", { token: owner.token, body: webPayload() });
    const attacker = "192.0.2.99";
    const statuses: number[] = [];
    for (let i = 0; i < 24; i += 1) {
      statuses.push((await call("GET", `/api/public/shares/${i.toString().padStart(43, "x")}`, { ip: attacker })).status);
    }
    expect(statuses.slice(0, 20).every((s) => s === 404)).toBe(true);
    expect(statuses.slice(20).every((s) => s === 429)).toBe(true);
    // 攻撃元からは、有効なリンクも一時的に見られない（429）が、別のIPからは普通に見られる
    expect((await call("GET", `/api/public/shares/${share.body.token}`, { ip: attacker })).status).toBe(429);
    expect((await call("GET", `/api/public/shares/${share.body.token}`, { ip: "192.0.2.50" })).status).toBe(200);
  });

  it("制限は、サーバーのメモリではなく、Firestoreに記録される（IPはハッシュ）", async () => {
    await call("GET", `/api/public/shares/${"y".repeat(43)}`, { ip: "192.0.2.77" });
    const snap = await db().collection("rateLimits").get();
    expect(snap.size).toBe(1);
    expect(JSON.stringify([snap.docs[0].id, snap.docs[0].data()])).not.toContain("192.0.2.77");
  });

  it("1時間たつと、制限が解ける", async () => {
    const ip = "192.0.2.123";
    for (let i = 0; i < 21; i += 1) await call("GET", `/api/public/shares/${i.toString().padStart(43, "z")}`, { ip });
    expect((await call("GET", `/api/public/shares/${"q".repeat(43)}`, { ip })).status).toBe(429);
    setClockForTests(() => addHours(new Date(), 2));
    expect((await call("GET", `/api/public/shares/${"q".repeat(43)}`, { ip })).status).toBe(404);
  });

  it("招待ページの匿名取得にも、同じ制限がかかる", async () => {
    const ip = "192.0.2.200";
    let last = 0;
    for (let i = 0; i < 22; i += 1) last = (await call("GET", `/api/public/invitations/${i.toString().padStart(43, "w")}`, { ip })).status;
    expect(last).toBe(429);
  });
});
