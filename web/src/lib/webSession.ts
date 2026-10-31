import { adminAuth } from "./firebase";
import { displayNameSchema } from "./schema";
import { putMe, userRef } from "./users";

/** Web サイトのログイン（Googleの認可コードの流れ）。ふとのアプリと同じ Firebase アカウントになる。 */
export const SESSION_COOKIE = "futo_session";
export const STATE_COOKIE = "futo_oauth_state";
export const SESSION_DAYS = 5;

export interface WebAuthConfig {
  clientId: string;
  clientSecret: string;
  firebaseApiKey: string;
}

export function webAuthConfig(env: NodeJS.ProcessEnv = process.env): WebAuthConfig | null {
  const clientId = env.GOOGLE_WEB_CLIENT_ID;
  const clientSecret = env.GOOGLE_WEB_CLIENT_SECRET;
  const firebaseApiKey = env.FIREBASE_WEB_API_KEY;
  if (!clientId || !clientSecret || !firebaseApiKey) return null;
  return { clientId, clientSecret, firebaseApiKey };
}

export function googleAuthUrl(config: WebAuthConfig, redirectUri: string, state: string): string {
  const params = new URLSearchParams({
    client_id: config.clientId,
    redirect_uri: redirectUri,
    response_type: "code",
    // 名前を初期の表示名に使うだけ。メール・写真・Drive は求めない
    scope: "openid profile",
    state,
    prompt: "select_account",
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${params}`;
}

/** 認可コードを、Firebase のアカウント（IDトークン）に替える。 */
export async function exchangeCode(config: WebAuthConfig, code: string, redirectUri: string, fetcher: typeof fetch = fetch): Promise<{ firebaseIdToken: string; uid: string; name?: string }> {
  const tokenResponse = await fetcher("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ code, client_id: config.clientId, client_secret: config.clientSecret, redirect_uri: redirectUri, grant_type: "authorization_code" }),
  });
  if (!tokenResponse.ok) throw new Error("google_token_failed");
  const token = (await tokenResponse.json()) as { id_token?: string };
  if (!token.id_token) throw new Error("google_token_failed");
  const signIn = await fetcher(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=${encodeURIComponent(config.firebaseApiKey)}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ postBody: `id_token=${token.id_token}&providerId=google.com`, requestUri: new URL(redirectUri).origin, returnIdpCredential: true, returnSecureToken: true }),
  });
  if (!signIn.ok) throw new Error("firebase_sign_in_failed");
  const result = (await signIn.json()) as { idToken?: string; localId?: string; displayName?: string };
  if (!result.idToken || !result.localId) throw new Error("firebase_sign_in_failed");
  return { firebaseIdToken: result.idToken, uid: result.localId, name: result.displayName };
}

/** アカウントが無ければ、Googleの名前（1〜20文字）で作る。アプリの初回ログインと同じ。 */
export async function ensureProfile(uid: string, providerName?: string): Promise<void> {
  const snap = await userRef(uid).get();
  if (snap.exists) return;
  const trimmed = [...(providerName ?? "").normalize("NFC").trim()].slice(0, 20).join("");
  const name = displayNameSchema.safeParse(trimmed).success ? trimmed : "ふと";
  await putMe(uid, name);
}

export async function createSessionCookie(firebaseIdToken: string): Promise<string> {
  return adminAuth().createSessionCookie(firebaseIdToken, { expiresIn: SESSION_DAYS * 24 * 60 * 60 * 1000 });
}

/** Cookie から、ログイン中のアカウントを読む。無効・期限切れなら null。 */
export async function readSessionUid(cookieValue: string | undefined): Promise<string | null> {
  if (!cookieValue) return null;
  try {
    const decoded = await adminAuth().verifySessionCookie(cookieValue, true);
    return decoded.uid;
  } catch {
    return null;
  }
}

export function parseCookie(header: string | null, name: string): string | undefined {
  for (const part of (header ?? "").split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return decodeURIComponent(rest.join("="));
  }
  return undefined;
}

export function cookieHeader(name: string, value: string, maxAgeSeconds: number): string {
  return `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${maxAgeSeconds}; HttpOnly; Secure; SameSite=Lax`;
}

/** 別のサイトからの送信は受け付けない（Origin が、このサイトのものか確かめる）。 */
export function sameOrigin(req: Request): boolean {
  const origin = req.headers.get("origin");
  if (!origin) return false;
  const base = process.env.PUBLIC_BASE_URL ? new URL(process.env.PUBLIC_BASE_URL).origin : new URL(req.url).origin;
  return origin === base;
}

