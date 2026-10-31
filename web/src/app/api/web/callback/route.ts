import { publicUrl } from "@/lib/publicUrl";
import { cookieHeader, createSessionCookie, ensureProfile, exchangeCode, parseCookie, SESSION_COOKIE, SESSION_DAYS, STATE_COOKIE, webAuthConfig } from "@/lib/webSession";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

const back = (status: string, extra?: string[]) => {
  const headers = new Headers({ location: `/support?status=${status}` });
  headers.append("set-cookie", cookieHeader(STATE_COOKIE, "", 0));
  for (const cookie of extra ?? []) headers.append("set-cookie", cookie);
  return new Response(null, { status: 302, headers });
};

/** Google から戻ったとき。state を確かめ、コードを Firebase のアカウントに替えて、ログインの Cookie を出す。 */
export async function GET(req: Request) {
  const config = webAuthConfig();
  if (!config) return back("unavailable");
  const url = new URL(req.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const expected = parseCookie(req.headers.get("cookie"), STATE_COOKIE);
  if (!code || !state || !expected || state !== expected) return back("failed");
  try {
    const origin = process.env.PUBLIC_BASE_URL ? "" : url.origin;
    const { firebaseIdToken, uid, name } = await exchangeCode(config, code, origin + publicUrl("/api/web/callback"));
    await ensureProfile(uid, name);
    const session = await createSessionCookie(firebaseIdToken);
    return back("signed_in", [cookieHeader(SESSION_COOKIE, session, SESSION_DAYS * 24 * 60 * 60)]);
  } catch {
    return back("failed");
  }
}
