import { randomBytes } from "node:crypto";
import { publicUrl } from "@/lib/publicUrl";
import { cookieHeader, googleAuthUrl, STATE_COOKIE, webAuthConfig } from "@/lib/webSession";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** Web サイトの「Google でログイン」。Google の同意画面へ送る。 */
export function GET(req: Request) {
  const config = webAuthConfig();
  if (!config) return new Response(null, { status: 302, headers: { location: "/support?status=unavailable" } });
  const origin = process.env.PUBLIC_BASE_URL ? "" : new URL(req.url).origin;
  const redirectUri = origin + publicUrl("/api/web/callback");
  const state = randomBytes(24).toString("hex");
  const headers = new Headers({ location: googleAuthUrl(config, redirectUri, state) });
  headers.append("set-cookie", cookieHeader(STATE_COOKIE, state, 600));
  return new Response(null, { status: 302, headers });
}
