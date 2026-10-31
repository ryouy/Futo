import { generateKeyPairSync, verify } from "node:crypto";
import { describe, expect, it } from "vitest";
import { appleClientSecret, appleConfig, exchangeAppleCode, revokeAppleToken } from "@/lib/apple";

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const config = { teamId: "TEAM123456", keyId: "KEY1234567", privateKey: pem, clientId: "com.ryouy.futo" };

describe("Apple：接続の取り消し用の部品", () => {
  it("設定が1つでも足りなければ無効。改行の \\n は戻す", () => {
    const env = { APPLE_TEAM_ID: "t", APPLE_KEY_ID: "k", APPLE_PRIVATE_KEY: "a\\nb", IOS_BUNDLE_ID: "c" } as unknown as NodeJS.ProcessEnv;
    expect(appleConfig(env)?.privateKey).toBe("a\nb");
    for (const key of Object.keys(env)) {
      const partial = { ...env };
      delete (partial as Record<string, unknown>)[key];
      expect(appleConfig(partial), `${key} が無いときは無効`).toBeNull();
    }
  });

  it("client_secret は ES256 の JWT で、署名を公開鍵で確かめられる", () => {
    const jwt = appleClientSecret(config, 1_800_000_000);
    const [header, payload, signature] = jwt.split(".");
    expect(JSON.parse(Buffer.from(header, "base64url").toString())).toEqual({ alg: "ES256", kid: "KEY1234567", typ: "JWT" });
    expect(JSON.parse(Buffer.from(payload, "base64url").toString())).toEqual({ iss: "TEAM123456", iat: 1_800_000_000, exp: 1_800_000_600, aud: "https://appleid.apple.com", sub: "com.ryouy.futo" });
    expect(verify("sha256", Buffer.from(`${header}.${payload}`), { key: publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url"))).toBe(true);
  });

  const fake = (status: number, body: unknown): typeof fetch => (async () => new Response(JSON.stringify(body), { status })) as unknown as typeof fetch;

  it("認可コードを、トークンに替える。失敗は拒否", async () => {
    expect(await exchangeAppleCode(config, "code-1234", 1_800_000_000, fake(200, { refresh_token: "rt" }))).toBe("rt");
    await expect(exchangeAppleCode(config, "bad-code", 1_800_000_000, fake(400, { error: "invalid_grant" }))).rejects.toThrow();
    await expect(exchangeAppleCode(config, "code-1234", 1_800_000_000, fake(200, {}))).rejects.toThrow();
  });

  it("取り消し：成功と、すでに無効（400）は完了。それ以外の失敗は、やり直せるよう、エラーにする", async () => {
    await expect(revokeAppleToken(config, "rt", 1_800_000_000, fake(200, {}))).resolves.toBeUndefined();
    await expect(revokeAppleToken(config, "rt", 1_800_000_000, fake(400, { error: "invalid_grant" }))).resolves.toBeUndefined();
    await expect(revokeAppleToken(config, "rt", 1_800_000_000, fake(500, {}))).rejects.toThrow();
  });
});
