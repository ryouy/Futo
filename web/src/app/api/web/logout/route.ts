import { cookieHeader, SESSION_COOKIE } from "@/lib/webSession";

export const dynamic = "force-dynamic";

export function POST() {
  return new Response(JSON.stringify({ ok: true }), { status: 200, headers: { "content-type": "application/json", "set-cookie": cookieHeader(SESSION_COOKIE, "", 0) } });
}
