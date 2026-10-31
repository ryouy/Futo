import { createCheckout, type WebPlan } from "@/lib/billing";
import { ApiError, handle, json, readJson } from "@/lib/routeHelpers";
import { billingConfig } from "@/lib/stripe";
import { parseCookie, readSessionUid, sameOrigin, SESSION_COOKIE } from "@/lib/webSession";
import { publicUrl } from "@/lib/publicUrl";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const POST = (req: Request) =>
  handle(async () => {
    const config = billingConfig();
    if (!config) throw new ApiError(503, "billing_not_configured");
    if (!sameOrigin(req)) throw new ApiError(403, "forbidden");
    const uid = await readSessionUid(parseCookie(req.headers.get("cookie"), SESSION_COOKIE));
    if (!uid) throw new ApiError(401, "unauthorized");
    const body = (await readJson(req)) as { plan?: unknown };
    if (body.plan !== "adFree" && body.plan !== "support") throw new ApiError(400, "invalid_plan");
    const base = process.env.PUBLIC_BASE_URL ? publicUrl("") : new URL(req.url).origin;
    return json(200, { url: await createCheckout(config, uid, body.plan as WebPlan, base) });
  });
