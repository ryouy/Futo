import { handle, json, requireUser, type Ctx } from "@/lib/routeHelpers";
import { removeReceivedFriendShare } from "@/lib/friendShares";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** 届いた記録を、自分の側だけ、削除する。 */
export const DELETE = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    await removeReceivedFriendShare(user.uid, (await ctx.params).id);
    return json(200, { ok: true });
  });
