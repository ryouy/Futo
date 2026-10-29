import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { publicUrl } from "@/lib/publicUrl";
import { webSharePayload } from "@/lib/schema";
import { createWebShare, listShares } from "@/lib/shares";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    const payload = webSharePayload.parse(await readJson(req));
    const created = await createWebShare(user.uid, payload);
    return json(created.replay ? 200 : 201, { ...created, url: created.token ? publicUrl(`/s/${created.token}`) : null });
  });

export const GET = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req, { checkRevoked: false });
    const url = new URL(req.url);
    return json(200, await listShares(user.uid, Number(url.searchParams.get("limit") ?? "20"), url.searchParams.get("cursor") ?? undefined));
  });
