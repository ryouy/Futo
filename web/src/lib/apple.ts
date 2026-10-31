import { createPrivateKey, sign } from "node:crypto";
import { adminAuth } from "./firebase";
import { ApiError } from "./http";
import { userRef } from "./users";

/**
 * 「Appleで続ける」で作ったアカウントの、Apple側の接続を解除するための部品。
 * アカウントを削除するとき、Apple の規約に沿って、アプリへの接続（トークン）を取り消す。
 * Apple の鍵（.p8）などは、環境変数だけに置く。未設定なら、この処理はできない（ログイン自体は、影響を受けない）。
 */
export interface AppleConfig {
  teamId: string;
  keyId: string;
  privateKey: string;
  clientId: string;
}

export function appleConfig(env: NodeJS.ProcessEnv = process.env): AppleConfig | null {
  const teamId = env.APPLE_TEAM_ID;
  const keyId = env.APPLE_KEY_ID;
  const privateKey = env.APPLE_PRIVATE_KEY;
  const clientId = env.IOS_BUNDLE_ID;
  if (!teamId || !keyId || !privateKey || !clientId) return null;
  // Vercelの環境変数では、改行が \n の文字として入る
  return { teamId, keyId, privateKey: privateKey.replace(/\\n/g, "\n"), clientId };
}

const b64url = (input: Buffer | string) => Buffer.from(input).toString("base64url");

/** Apple の token / revoke 用の client_secret（ES256 の JWT）。 */
export function appleClientSecret(config: AppleConfig, nowSeconds: number): string {
  const header = b64url(JSON.stringify({ alg: "ES256", kid: config.keyId, typ: "JWT" }));
  const payload = b64url(JSON.stringify({ iss: config.teamId, iat: nowSeconds, exp: nowSeconds + 600, aud: "https://appleid.apple.com", sub: config.clientId }));
  const signature = sign("sha256", Buffer.from(`${header}.${payload}`), { key: createPrivateKey(config.privateKey), dsaEncoding: "ieee-p1363" });
  return `${header}.${payload}.${b64url(signature)}`;
}

async function appleForm(path: string, fields: Record<string, string>, fetcher: typeof fetch): Promise<{ ok: boolean; status: number; body: Record<string, unknown> }> {
  const response = await fetcher(`https://appleid.apple.com/auth/${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields),
  });
  return { ok: response.ok, status: response.status, body: (await response.json().catch(() => ({}))) as Record<string, unknown> };
}

/** 認可コードを、取り消しに使うトークン（refresh_token）に替える。 */
export async function exchangeAppleCode(config: AppleConfig, code: string, nowSeconds: number, fetcher: typeof fetch = fetch): Promise<string> {
  const result = await appleForm("token", { client_id: config.clientId, client_secret: appleClientSecret(config, nowSeconds), code, grant_type: "authorization_code" }, fetcher);
  const token = result.body.refresh_token;
  if (!result.ok || typeof token !== "string") throw new ApiError(400, "apple_code_invalid");
  return token;
}

/** Apple への接続を取り消す。すでに無効（400）なら、取り消し済みと同じ。 */
export async function revokeAppleToken(config: AppleConfig, refreshToken: string, nowSeconds: number, fetcher: typeof fetch = fetch): Promise<void> {
  const result = await appleForm("revoke", { client_id: config.clientId, client_secret: appleClientSecret(config, nowSeconds), token: refreshToken, token_type_hint: "refresh_token" }, fetcher);
  if (!result.ok && result.status !== 400) throw new ApiError(502, "apple_unavailable");
}

/** ログインしてきたアカウントが、Apple で作られたものか（Firebase の記録で確かめる）。 */
export async function isAppleAccount(uid: string): Promise<boolean> {
  const record = await adminAuth().getUser(uid);
  return record.providerData.some((p) => p.providerId === "apple.com");
}

/** アプリが預けた認可コードを、トークンに替えて、アカウントに控える（削除のときの取り消し用）。 */
export async function linkAppleAccount(uid: string, code: string, nowSeconds: number): Promise<boolean> {
  const config = appleConfig();
  if (!config) return false; // 設定が無ければ、控えられない（ログインには影響しない）
  if (!(await isAppleAccount(uid))) throw new ApiError(400, "not_apple_account");
  const refreshToken = await exchangeAppleCode(config, code, nowSeconds);
  await userRef(uid).update({ appleRefreshToken: refreshToken });
  return true;
}

/** アカウント削除のとき、控えたトークンがあれば、Apple への接続を取り消す。 */
export async function revokeAppleForUser(uid: string, nowSeconds: number): Promise<void> {
  const token = (await userRef(uid).get()).data()?.appleRefreshToken;
  if (typeof token !== "string" || !token) return;
  const config = appleConfig();
  if (!config) return;
  await revokeAppleToken(config, token, nowSeconds);
}
