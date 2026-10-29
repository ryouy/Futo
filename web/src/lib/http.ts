import { ZodError } from "zod";
import { ConfigError } from "./firebase";

/** 呼び出し元に返してよい、分類済みのエラー。内部の詳細やトークンは載せない。 */
export class ApiError extends Error {
  constructor(
    public status: number,
    public code: string,
  ) {
    super(code);
    this.name = "ApiError";
  }
}

export const NO_STORE = { "Cache-Control": "private, no-store", "X-Robots-Tag": "noindex, nofollow, noarchive" };

export function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...NO_STORE },
  });
}

/** 本文の初期上限（32KiB）。端末の全履歴を送らせない。 */
export const MAX_BODY_BYTES = 32 * 1024;

export async function readJson(req: Request): Promise<unknown> {
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) throw new ApiError(413, "payload_too_large");
  const text = await req.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) throw new ApiError(413, "payload_too_large");
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new ApiError(400, "invalid_json");
  }
}

/** どのAPIも、この関数を通す。例外を分類して返し、トークンや内部情報はログに出さない。 */
export async function handle(fn: () => Promise<Response>): Promise<Response> {
  try {
    return await fn();
  } catch (error) {
    if (error instanceof ApiError) return json(error.status, { error: error.code });
    if (error instanceof ZodError) return json(400, { error: "invalid_request" });
    if (error instanceof ConfigError) return json(503, { error: "not_configured" });
    // 同時操作の競合（Firestoreのトランザクションが再試行の上限に達した）。もう一度試せば通る
    const code = (error as { code?: unknown }).code;
    const message = error instanceof Error ? error.message : "";
    if (code === 10 || code === "aborted" || code === "ABORTED" || /Transaction is invalid or closed/.test(message)) {
      return json(409, { error: "conflict" });
    }
    // 想定外：原因の種類だけを記録する（リクエスト内容・トークン・個人の統計は出さない）
    if (process.env.FUTO_DEBUG_ERRORS === "1") console.error("debug_error_message", error instanceof Error ? error.message.slice(0, 300) : error);
    console.error("unexpected_error", error instanceof Error ? error.name : "unknown", typeof (error as { code?: unknown }).code === "undefined" ? "" : String((error as { code?: unknown }).code));
    return json(500, { error: "internal" });
  }
}
