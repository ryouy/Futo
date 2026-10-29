import { requireUser } from "./auth";
import { clientKey } from "./rateLimit";

export { handle, json, readJson, ApiError } from "./http";
export { requireUser, clientKey };

/** Next.js 15のルートハンドラーの第2引数（paramsはPromise） */
export type Ctx<T extends Record<string, string>> = { params: Promise<T> };
