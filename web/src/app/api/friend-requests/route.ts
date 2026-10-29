import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { z } from "zod";
import { createFriendRequest } from "@/lib/friends";

const body = z.object({ token: z.string().max(100).optional(), code: z.string().max(40).optional() }).strict()
  .refine((v) => Boolean(v.token) !== Boolean(v.code), "exactly_one");

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    const input = body.parse(await readJson(req));
    return json(201, await createFriendRequest(user.uid, input, clientKey(req)));
  });
