import { beforeEach, describe, expect, it } from "vitest";
import { adminAuth, call, newUser, resetAll, unsignedJwt } from "./helpers";

beforeEach(resetAll);

describe("認証（Firebase IDトークン）", () => {
  it("トークンなし・不正な形式は401", async () => {
    expect((await call("GET", "/api/me")).status).toBe(401);
    expect((await call("GET", "/api/me", { headers: { authorization: "Basic abc" } })).status).toBe(401);
    expect((await call("GET", "/api/me", { token: "not-a-jwt" })).status).toBe(401);
  });

  it("本物のIDトークンは通る", async () => {
    const user = await newUser("たろう");
    const response = await call("GET", "/api/me", { token: user.token });
    expect(response.status).toBe(200);
    expect(response.body).toMatchObject({ uid: user.uid, displayName: "たろう" });
  });

  it("別プロジェクト向けの偽造トークンを拒否する", async () => {
    const user = await newUser();
    const now = Math.floor(Date.now() / 1000);
    const forged = unsignedJwt({ aud: "other-project", iss: "https://securetoken.google.com/other-project", sub: user.uid, user_id: user.uid, iat: now, exp: now + 3600, auth_time: now });
    expect((await call("GET", "/api/me", { token: forged })).status).toBe(401);
  });

  it("期限切れのトークンを拒否する", async () => {
    const user = await newUser();
    const past = Math.floor(Date.now() / 1000) - 7200;
    const expired = unsignedJwt({ aud: "demo-futo", iss: "https://securetoken.google.com/demo-futo", sub: user.uid, user_id: user.uid, iat: past, exp: past + 3600, auth_time: past });
    expect((await call("GET", "/api/me", { token: expired })).status).toBe(401);
  });

  it("失効（revoke）したトークンは、書き込み操作で拒否される", async () => {
    const user = await newUser();
    await new Promise((resolve) => setTimeout(resolve, 1100)); // revoke時刻は秒単位
    await adminAuth().revokeRefreshTokens(user.uid);
    expect((await call("PUT", "/api/me", { token: user.token, body: { displayName: "あたらしい" } })).status).toBe(401);
  });

  it("エラー応答に、内部情報やトークンを含めない", async () => {
    const response = await call("GET", "/api/me", { token: "secret-looking-token" });
    expect(response.text).not.toContain("secret-looking-token");
    expect(Object.keys(response.body)).toEqual(["error"]);
  });
});

describe("プロフィール（表示名）", () => {
  it("プロフィール未作成だと共有操作はできない（個人の機能には影響しない）", async () => {
    const user = await newUser("x", { profile: false });
    expect((await call("GET", "/api/me", { token: user.token })).status).toBe(404);
    expect((await call("POST", "/api/invitations", { token: user.token })).status).toBe(403);
  });

  it.each([
    ["空", ""],
    ["空白だけ", "   "],
    ["改行入り", "あ\nい"],
    ["制御文字", "あ\u0007い"],
    ["21文字", "あ".repeat(21)],
  ])("不正な表示名を拒否する: %s", async (_label, name) => {
    const user = await newUser("ok", { profile: false });
    expect((await call("PUT", "/api/me", { token: user.token, body: { displayName: name } })).status).toBe(400);
  });

  it("1〜20文字は通り、前後の空白は除かれる。Googleの実名やメールは受け取らない", async () => {
    const user = await newUser("ok", { profile: false });
    const response = await call("PUT", "/api/me", { token: user.token, body: { displayName: "  ふとのユーザー  ", email: "x@example.com", photoURL: "x" } });
    expect(response.status).toBe(200);
    expect(response.body.displayName).toBe("ふとのユーザー");
    expect(JSON.stringify(response.body)).not.toContain("example.com");
  });
});
