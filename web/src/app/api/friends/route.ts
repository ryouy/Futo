import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { listFriends } from "@/lib/friends";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const GET = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req, { checkRevoked: false });
    return json(200, await listFriends(user.uid));
  });
