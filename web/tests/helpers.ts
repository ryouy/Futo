import { randomUUID } from "node:crypto";
import { setClockForTests } from "@/lib/clock";
import { adminAuth, db } from "@/lib/firebase";

type Handler = (req: Request, ctx: { params: Promise<Record<string, string>> }) => Promise<Response>;
type Module = Record<string, Handler>;

/** 実際のルートハンドラーを、HTTPサーバーなしで直接呼ぶ（認証・検証・Firestoreはすべて本物）。 */
const routes: [string, () => Promise<Module>][] = [
  ["/api/me", () => import("@/app/api/me/route") as unknown as Promise<Module>],
  ["/api/shares", () => import("@/app/api/shares/route") as unknown as Promise<Module>],
  ["/api/shares/:id", () => import("@/app/api/shares/[id]/route") as unknown as Promise<Module>],
  ["/api/shares/:id/rotate", () => import("@/app/api/shares/[id]/rotate/route") as unknown as Promise<Module>],
  ["/api/public/shares/:token", () => import("@/app/api/public/shares/[token]/route") as unknown as Promise<Module>],
  ["/api/public/reports", () => import("@/app/api/public/reports/route") as unknown as Promise<Module>],
  ["/api/invitations", () => import("@/app/api/invitations/route") as unknown as Promise<Module>],
  ["/api/invitations/:id", () => import("@/app/api/invitations/[id]/route") as unknown as Promise<Module>],
  ["/api/public/invitations/:token", () => import("@/app/api/public/invitations/[token]/route") as unknown as Promise<Module>],
  ["/api/friend-requests", () => import("@/app/api/friend-requests/route") as unknown as Promise<Module>],
  ["/api/friend-requests/:id", () => import("@/app/api/friend-requests/[id]/route") as unknown as Promise<Module>],
  ["/api/friend-requests/:id/accept", () => import("@/app/api/friend-requests/[id]/accept/route") as unknown as Promise<Module>],
  ["/api/friend-requests/:id/decline", () => import("@/app/api/friend-requests/[id]/decline/route") as unknown as Promise<Module>],
  ["/api/friends", () => import("@/app/api/friends/route") as unknown as Promise<Module>],
  ["/api/friends/:id", () => import("@/app/api/friends/[id]/route") as unknown as Promise<Module>],
  ["/api/blocks/:id", () => import("@/app/api/blocks/[id]/route") as unknown as Promise<Module>],
  ["/api/friend-shares", () => import("@/app/api/friend-shares/route") as unknown as Promise<Module>],
  ["/api/friend-shares/:id", () => import("@/app/api/friend-shares/[id]/route") as unknown as Promise<Module>],
  ["/api/reports", () => import("@/app/api/reports/route") as unknown as Promise<Module>],
];

export interface CallOptions {
  token?: string;
  body?: unknown;
  rawBody?: string;
  ip?: string;
  headers?: Record<string, string>;
}

export async function call(method: string, path: string, options: CallOptions = {}) {
  const [pathname] = path.split("?");
  for (const [pattern, load] of routes) {
    const names: string[] = [];
    const regex = new RegExp("^" + pattern.replace(/:(\w+)/g, (_, name) => (names.push(name), "([^/]+)")) + "$");
    const match = regex.exec(pathname);
    if (!match) continue;
    const params = Object.fromEntries(names.map((name, i) => [name, decodeURIComponent(match[i + 1])]));
    const handler = (await load())[method];
    if (!handler) throw new Error(`no ${method} handler for ${pattern}`);
    const headers: Record<string, string> = { "content-type": "application/json", "x-forwarded-for": options.ip ?? "203.0.113.1", ...(options.headers ?? {}) };
    if (options.token) headers.authorization = `Bearer ${options.token}`;
    const hasBody = options.body !== undefined || options.rawBody !== undefined;
    const request = new Request(`https://test.local${path}`, {
      method,
      headers,
      body: hasBody ? (options.rawBody ?? JSON.stringify(options.body)) : undefined,
    });
    const response = await handler(request, { params: Promise.resolve(params) });
    const text = await response.text();
    return { status: response.status, headers: response.headers, body: text ? JSON.parse(text) : null, text };
  }
  throw new Error(`no route for ${path}`);
}

export interface TestUser {
  uid: string;
  token: string;
  name: string;
}

/** Authエミュレーターで本物のFirebase IDトークンを発行する。 */
export async function newUser(name = "テストユーザー", options: { profile?: boolean } = {}): Promise<TestUser> {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const response = await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email: `${randomUUID()}@example.test`, password: "password123", returnSecureToken: true }),
  });
  const data = (await response.json()) as { idToken: string; localId: string };
  const user = { uid: data.localId, token: data.idToken, name };
  if (options.profile !== false) {
    const put = await call("PUT", "/api/me", { token: user.token, body: { displayName: name } });
    if (put.status !== 200) throw new Error(`profile failed: ${put.status}`);
  }
  return user;
}

export async function resetAll(): Promise<void> {
  setClockForTests(null);
  const project = "demo-futo";
  await fetch(`http://${process.env.FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${project}/databases/(default)/documents`, { method: "DELETE" });
  await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/emulator/v1/projects/${project}/accounts`, { method: "DELETE" });
}

/** 共有する統計のペイロード。選んだ項目だけを入れる。 */
export function webPayload(overrides: Record<string, unknown> = {}) {
  return {
    period: "thisWeek",
    periodStart: "2027-01-10T19:00:00.000Z",
    periodEnd: "2027-01-17T19:00:00.000Z",
    timezone: "Asia/Tokyo",
    isPartial: true,
    showName: true,
    counts: { wantsToUse: 5, deferred: 3, interrupted: 1 },
    expiresInDays: 7,
    idempotencyKey: randomUUID(),
    ...overrides,
  };
}

export function friendPayload(recipientUids: string[], overrides: Record<string, unknown> = {}) {
  const { expiresInDays: _drop, ...rest } = webPayload();
  return { ...rest, recipientUids, ...overrides };
}

/** Firestore全体から、指定の文字列を含むドキュメントを探す（生トークンが保存されていないことの確認用）。 */
export async function docsContaining(needle: string): Promise<string[]> {
  const found: string[] = [];
  for (const collection of await db().listCollections()) {
    const snap = await collection.get();
    for (const doc of snap.docs) {
      if (doc.id.includes(needle) || JSON.stringify(doc.data()).includes(needle)) found.push(`${collection.id}/${doc.id}`);
    }
  }
  return found;
}

export { adminAuth, db, setClockForTests };

/** alg:none の、署名のないJWTを作る（偽造・期限切れ・別プロジェクトの確認用）。 */
export function unsignedJwt(claims: Record<string, unknown>): string {
  const encode = (value: unknown) => Buffer.from(JSON.stringify(value)).toString("base64url");
  return `${encode({ alg: "none", typ: "JWT" })}.${encode(claims)}.`;
}
