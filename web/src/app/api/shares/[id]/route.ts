import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { getOwnShare, revokeShare } from "@/lib/shares";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const GET = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req, { checkRevoked: false });
    return json(200, await getOwnShare(user.uid, (await ctx.params).id));
  });

export const DELETE = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    await revokeShare(user.uid, (await ctx.params).id);
    return json(200, { ok: true });
  });
