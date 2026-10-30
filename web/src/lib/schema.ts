import { z } from "zod";

const count = z.number().int().min(0).max(100_000);

/** 定型のひとこと。自由記述は受け取らず、IDだけを受け取る。 */
export const PHRASES = {
  p1: "こんな感じでした。",
  p2: "ひと呼吸の記録を、少しだけ共有します。",
  p3: "ふと、立ち止まった記録です。",
} as const;
export type PhraseId = keyof typeof PHRASES;

/** 公開表示名：1〜20文字。空白だけ・制御文字・改行を拒否する。 */
export const displayNameSchema = z
  .string()
  .transform((value) => value.normalize("NFC").trim())
  .refine((value) => value.length >= 1 && [...value].length <= 20, "length")
  .refine((value) => !/[\p{Cc}\p{Cf}\u2028\u2029]/u.test(value), "control");

/**
 * フレンドへの一言（自由入力）。フレンド共有だけで使い、Webの公開リンクでは受け付けない。
 * 1〜60文字。制御文字・URL（迷惑・誘導の防止）は拒否する。
 */
export const MESSAGE_MAX = 60;
export const messageSchema = z
  .string()
  .transform((value) => value.normalize("NFC").trim())
  .refine((value) => value.length >= 1 && [...value].length <= MESSAGE_MAX, "length")
  .refine((value) => !/[\p{Cc}\p{Cf}\u2028\u2029]/u.test(value), "control")
  .refine((value) => !/:\/\/|www\.|\b[a-z0-9-]+\.(com|net|org|jp|io|co|app|me|ly|xyz)\b/i.test(value), "url");

/** アプリ名（解除した対象の表示名）。1〜40文字、制御文字なし。 */
const appNameSchema = z
  .string()
  .transform((value) => value.normalize("NFC").trim())
  .refine((value) => value.length >= 1 && [...value].length <= 40, "length")
  .refine((value) => !/[\p{Cc}\p{Cf}\u2028\u2029]/u.test(value), "control");

export const MAX_APPS = 10;
const appsSchema = z.array(z.object({ name: appNameSchema, count }).strict()).min(1).max(MAX_APPS);

/** 共有する統計。選んだ項目だけを送り、選ばなかった項目はキー自体を付けない。 */
const statsShape = {
  period: z.enum(["thisWeek", "lastWeek", "all"]),
  periodStart: z.string().datetime(),
  periodEnd: z.string().datetime(),
  timezone: z.string().min(1).max(64),
  isPartial: z.boolean(),
  showName: z.boolean(),
  counts: z.object({ wantsToUse: count, deferred: count, interrupted: count }).strict().optional(),
  purposes: z
    .object({ contact: count, research: count, break: count, noReason: count, unanswered: count })
    .strict()
    .optional(),
  feelings: z.object({ satisfied: count, neutral: count, wishedLess: count }).strict().optional(),
  phraseId: z.enum(["p1", "p2", "p3"]).optional(),
  /** よく解除したアプリ名と回数（任意）。選んだときだけ送る */
  apps: appsSchema.optional(),
};

/** 週は最大8日。「全期間」は、最大10年。 */
const MAX_SPAN_DAYS = { week: 8, all: 3650 };

function checkStats(value: { period: string; periodStart: string; periodEnd: string; counts?: unknown; purposes?: unknown; feelings?: unknown; apps?: unknown; phraseId?: unknown }, ctx: z.RefinementCtx) {
  const start = Date.parse(value.periodStart);
  const end = Date.parse(value.periodEnd);
  const maxDays = value.period === "all" ? MAX_SPAN_DAYS.all : MAX_SPAN_DAYS.week;
  if (!(end > start) || end - start > maxDays * 86_400_000) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "period" });
  }
  // 全項目が未選択なら公開しない（ひとことだけの共有も作らない）
  if (!value.counts && !value.purposes && !value.feelings && !value.apps) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "nothing_selected" });
  }
}

export const webSharePayload = z
  .object({
    ...statsShape,
    expiresInDays: z.union([z.literal(1), z.literal(7), z.literal(30)]),
    idempotencyKey: z.string().uuid(),
  })
  .strict()
  .superRefine(checkStats);

export const friendSharePayload = z
  .object({
    ...statsShape,
    message: messageSchema.optional(),
    recipientUids: z.array(z.string().min(1).max(128)).min(1).max(50),
    idempotencyKey: z.string().uuid(),
  })
  .strict()
  .superRefine(checkStats);

/** 継続共有の更新：受信者は変えず、統計だけを差し替える。 */
export const friendShareUpdatePayload = z.object({ ...statsShape, message: messageSchema.optional() }).strict().superRefine(checkStats);

export type WebSharePayload = z.infer<typeof webSharePayload>;
export type FriendSharePayload = z.infer<typeof friendSharePayload>;

/** 保存・返却する統計のコピー。送られた項目だけを、型で絞って取り出す。 */
export interface StatsSnapshot {
  period: "thisWeek" | "lastWeek" | "all";
  periodStart: string;
  periodEnd: string;
  timezone: string;
  isPartial: boolean;
  counts?: { wantsToUse: number; deferred: number; interrupted: number };
  purposes?: { contact: number; research: number; break: number; noReason: number; unanswered: number };
  feelings?: { satisfied: number; neutral: number; wishedLess: number; answered: number };
  apps?: { name: string; count: number }[];
  phrase?: string;
  /** フレンドへの一言（自由入力）。フレンド共有だけ */
  message?: string;
}

export function snapshotFrom(payload: WebSharePayload | FriendSharePayload | z.infer<typeof friendShareUpdatePayload>): StatsSnapshot {
  const snapshot: StatsSnapshot = {
    period: payload.period,
    periodStart: payload.periodStart,
    periodEnd: payload.periodEnd,
    timezone: payload.timezone,
    isPartial: payload.isPartial,
  };
  if (payload.counts) snapshot.counts = { ...payload.counts };
  if (payload.purposes) snapshot.purposes = { ...payload.purposes };
  if (payload.apps) snapshot.apps = payload.apps.map((a) => ({ name: a.name, count: a.count }));
  if (payload.feelings) {
    // 満足感は、回答済み件数を分母とする。未回答の補完はしない。
    const { satisfied, neutral, wishedLess } = payload.feelings;
    snapshot.feelings = { satisfied, neutral, wishedLess, answered: satisfied + neutral + wishedLess };
  }
  if (payload.phraseId) snapshot.phrase = PHRASES[payload.phraseId];
  if ("message" in payload && payload.message) snapshot.message = payload.message;
  return snapshot;
}
