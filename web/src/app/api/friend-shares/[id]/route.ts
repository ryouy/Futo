import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { getFriendShare, revokeFriendShare } from "@/lib/friendShares";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const GET = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req, { checkRevoked: false });
    return json(200, await getFriendShare(user.uid, (await ctx.params).id));
  });

export const DELETE = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    await revokeFriendShare(user.uid, (await ctx.params).id);
    return json(200, { ok: true });
  });
