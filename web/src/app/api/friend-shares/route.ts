import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { createFriendShare, listReceivedFriendShares, listSentFriendShares } from "@/lib/friendShares";
import { friendSharePayload } from "@/lib/schema";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    const payload = friendSharePayload.parse(await readJson(req));
    const created = await createFriendShare(user.uid, payload);
    return json(created.replay ? 200 : 201, created);
  });

export const GET = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req, { checkRevoked: false });
    const role = new URL(req.url).searchParams.get("role") === "sent" ? "sent" : "received";
    return json(200, role === "sent" ? await listSentFriendShares(user.uid) : await listReceivedFriendShares(user.uid));
  });
