import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { publicUrl } from "@/lib/publicUrl";
import { rotateShare } from "@/lib/shares";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request, ctx: Ctx<{ id: string }>) =>
  handle(async () => {
    const user = await requireUser(req);
    const result = await rotateShare(user.uid, (await ctx.params).id);
    return json(200, { ...result, url: publicUrl(`/s/${result.token}`) });
  });
