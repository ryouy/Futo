import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { blockUser, unblockUser } from "@/lib/friends";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    await blockUser(user.uid, (await ctx.params).id);
    return json(200, { ok: true });
  });

export const DELETE = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    await unblockUser(user.uid, (await ctx.params).id);
    return json(200, { ok: true });
  });
