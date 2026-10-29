import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { declineFriendRequest } from "@/lib/friends";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    await declineFriendRequest(user.uid, (await ctx.params).id);
    return json(200, { ok: true });
  });
