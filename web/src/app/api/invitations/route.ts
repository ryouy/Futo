import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { createInvitation } from "@/lib/invitations";
import { publicUrl } from "@/lib/publicUrl";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    const created = await createInvitation(user.uid);
    return json(201, { ...created, url: publicUrl(`/i/${created.token}`) });
  });
