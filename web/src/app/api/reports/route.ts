import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { createReport } from "@/lib/reports";
import { reportPayload } from "@/lib/schema";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** 通報は、書き込みだけ。誰からも読み取れるAPIは作らない。 */
export const POST = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    return json(201, await createReport(user.uid, reportPayload.parse(await readJson(req))));
  });
