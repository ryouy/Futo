import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { removeFriend } from "@/lib/friends";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const DELETE = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    await removeFriend(user.uid, (await ctx.params).id);
    return json(200, { ok: true });
  });
