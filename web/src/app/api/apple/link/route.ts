import { linkAppleAccount } from "@/lib/apple";
import { now } from "@/lib/clock";
import { ApiError, handle, json, readJson, requireUser } from "@/lib/routeHelpers";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

/** 「Appleで続ける」の直後に、アプリが認可コードを預ける。アカウント削除のとき、Apple への接続を取り消すために使う。 */
export const POST = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    const body = (await readJson(req)) as { authorizationCode?: unknown };
    const code = body.authorizationCode;
    if (typeof code !== "string" || code.length < 8 || code.length > 2000) throw new ApiError(400, "invalid_code");
    const linked = await linkAppleAccount(user.uid, code, Math.floor(now().getTime() / 1000));
    return json(200, { linked });
  });
