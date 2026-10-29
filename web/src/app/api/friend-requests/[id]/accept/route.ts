import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { acceptFriendRequest } from "@/lib/friends";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    return json(200, await acceptFriendRequest(user.uid, (await ctx.params).id));
  });
