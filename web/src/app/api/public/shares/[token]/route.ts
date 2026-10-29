import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { getPublicShare } from "@/lib/shares";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** 匿名。有効な共有の、公開項目だけを返す。毎回、期限・取消を確認し、キャッシュしない。 */
export const GET = (req: Request, ctx: Ctx<{ token: string }>) =>
  handle(async () => json(200, await getPublicShare((await ctx.params).token, clientKey(req))));
