import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { publicReportPayload } from "@/lib/schema";
import { createPublicReport } from "@/lib/reports";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** Web共有ページからの匿名通報（IP単位の持続する制限つき）。 */
export const POST = (req: Request) =>
  handle(async () => {
    const payload = publicReportPayload.parse(await readJson(req));
    return json(201, await createPublicReport(payload.token, payload.reason, clientKey(req)));
  });
