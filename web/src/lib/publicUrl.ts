/** 共有・招待リンクの土台。PUBLIC_BASE_URL（本番の安定したドメイン）を使う。未設定なら相対パス。 */
export function publicUrl(path: string): string {
  const base = (process.env.PUBLIC_BASE_URL ?? "").replace(/\/+$/, "");
  return `${base}${path}`;
}
