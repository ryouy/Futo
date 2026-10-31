import type { ReactNode } from "react";

/** 日本語と英語を並べて出し、表示する言語は、ページ側（html の data-lang）が切り替える。 */
export function Bi({ ja, en }: { ja: ReactNode; en: ReactNode }) {
  return (
    <>
      <span className="ja">{ja}</span>
      <span className="en">{en}</span>
    </>
  );
}

export interface Bilingual {
  ja: string;
  en: string;
}
