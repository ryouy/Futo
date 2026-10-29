export const dynamic = "force-dynamic";

/** Universal Links。`/i/*`（フレンド招待）だけをアプリで開く。`/s/*`（統計共有）はWeb閲覧のまま。 */
export function GET() {
  const team = process.env.APPLE_TEAM_ID;
  const bundle = process.env.IOS_BUNDLE_ID;
  if (!team || !bundle) return new Response("not configured", { status: 404 });
  return new Response(
    JSON.stringify({ applinks: { details: [{ appIDs: [`${team}.${bundle}`], components: [{ "/": "/i/*" }] }] } }),
    { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=300" } },
  );
}
