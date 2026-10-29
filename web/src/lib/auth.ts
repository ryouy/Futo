import { adminAuth, ConfigError } from "./firebase";
import { ApiError } from "./http";

export interface AuthedUser {
  uid: string;
  /** 直近のサインイン時刻（秒）。アカウント削除の再認証確認に使う。 */
  authTime: number;
}

/**
 * Authorization: Bearer <Firebase IDトークン> を検証する。
 * 署名・対象プロジェクト・期限はAdmin SDKが検証する。書き込み系では、失効（revoke）の確認も行う。
 * GoogleのアクセストークンとFirebase IDトークンは別物で、ここで受け取るのは後者だけ。
 */
export async function requireUser(req: Request, options: { checkRevoked?: boolean } = {}): Promise<AuthedUser> {
  const header = req.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  if (!match) throw new ApiError(401, "unauthorized");
  try {
    const decoded = await adminAuth().verifyIdToken(match[1], options.checkRevoked ?? true);
    return { uid: decoded.uid, authTime: decoded.auth_time };
  } catch (error) {
    // サーバーの設定不備は、認証の失敗に見せかけず、503（未設定）として返す
    if (error instanceof ConfigError) throw error;
    // 偽造・期限切れ・別プロジェクト・失効は、理由を区別せず同じ応答にする
    throw new ApiError(401, "unauthorized");
  }
}
