import type { Metadata } from "next";
import "./globals.css";

// 検索・プレビューに統計や表示名を出さない。汎用の「ふとの振り返り」だけを使う
export const metadata: Metadata = {
  title: "ふとの振り返り",
  description: "ふとの振り返り",
  robots: { index: false, follow: false, noarchive: true, nocache: true },
  referrer: "no-referrer",
  openGraph: { title: "ふとの振り返り", description: "ふとの振り返り" },
  icons: { icon: "/favicon.png" },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja">
      <body>
        <header className="site">
          <img src="/logo.png" alt="" width={72} />
          <h1>ふと</h1>
        </header>
        <main>{children}</main>
        <footer className="site">
          ふと — 使う前に、ひと呼吸。
        </footer>
      </body>
    </html>
  );
}
