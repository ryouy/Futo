import { handle, json, requireUser } from "@/lib/routeHelpers";
import { listBlocked } from "@/lib/friends";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** 自分が削除（ブロック）した人の一覧。解除するための入口に使う。 */
export const GET = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req, { checkRevoked: false });
    return json(200, { items: await listBlocked(user.uid) });
  });
