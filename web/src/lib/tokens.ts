import { createHash, randomBytes, randomInt } from "node:crypto";

/** 32バイトの乱数をbase64urlにしたトークン（UIDや時刻から作らない）。 */
export function newToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

/** 形式だけを確かめる（存在確認の前に、明らかに違うものを捨てる）。 */
export function looksLikeToken(token: string): boolean {
  return /^[A-Za-z0-9_-]{43}$/.test(token);
}

// 紛らわしい文字（0/O, 1/I/L）を除いた、12文字の招待コード。6桁の連番にはしない。
const CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

export function newInviteCode(): string {
  let code = "";
  for (let i = 0; i < 12; i += 1) code += CODE_ALPHABET[randomInt(CODE_ALPHABET.length)];
  return code;
}

/** 入力されたコードを正規化（大文字・区切りの除去）。 */
export function normalizeCode(input: string): string {
  return input.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

export function looksLikeCode(code: string): boolean {
  return /^[ABCDEFGHJKMNPQRSTUVWXYZ23456789]{12}$/.test(code);
}

/** 2人のUIDを正規順に並べた、重複しないペアキー。 */
export function pairKey(a: string, b: string): string {
  return a < b ? `${a}_${b}` : `${b}_${a}`;
}

export function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}
