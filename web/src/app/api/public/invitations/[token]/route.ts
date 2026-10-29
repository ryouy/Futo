import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { getPublicInvitation } from "@/lib/invitations";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** 招待ページ用。GETでは、申請も消費もしない。仮名と有効状態だけを返す。 */
export const GET = (req: Request, ctx: Ctx<{ token: string }>) =>
  handle(async () => json(200, await getPublicInvitation((await ctx.params).token, clientKey(req))));
