import { handle, json, readJson, requireUser, clientKey, type Ctx } from "@/lib/routeHelpers";
import { beginAccountDeletion, purgeUserData } from "@/lib/accountDeletion";
import { getMe, parseAvatar, parseDisplayName, putMe } from "@/lib/users";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export const GET = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req, { checkRevoked: false });
    return json(200, await getMe(user.uid));
  });

export const PUT = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    const body = (await readJson(req)) as { displayName?: unknown; avatar?: unknown };
    return json(200, await putMe(user.uid, parseDisplayName(body.displayName), parseAvatar(body.avatar)));
  });

/** アカウント削除：直近のサインインを検証。未完了なら202を返し、呼び出し側が再度呼ぶ（再開できる）。 */
export const DELETE = (req: Request) =>
  handle(async () => {
    const user = await requireUser(req);
    await beginAccountDeletion(user.uid, user.authTime);
    const status = await purgeUserData(user.uid);
    return json(status === "deleted" ? 200 : 202, { status });
  });
