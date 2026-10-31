import type { Metadata } from "next";
import "./globals.css";
import { Bi } from "@/components/Bi";

// 検索・プレビューに統計や表示名を出さない。汎用の「ふとの振り返り」だけを使う
export const metadata: Metadata = {
  title: "ふとの振り返り",
  description: "ふとの振り返り",
  robots: { index: false, follow: false, noarchive: true, nocache: true },
  referrer: "no-referrer",
  openGraph: { title: "ふとの振り返り", description: "ふとの振り返り" },
  icons: { icon: "/favicon.png" },
};

// 言語：前に選んだものを優先し、なければブラウザの言語（日本語以外は English）。描画の前に決めて、ちらつきを防ぐ。
const langScript = `(function(){var d=document.documentElement,s;try{s=localStorage.getItem("futo-lang")}catch(e){}
var l=(s==="ja"||s==="en")?s:(((navigator.language||"ja").indexOf("ja")===0)?"ja":"en");
d.setAttribute("data-lang",l);d.lang=l;
document.addEventListener("click",function(e){var b=e.target&&e.target.closest&&e.target.closest("[data-set]");if(!b)return;var v=b.getAttribute("data-set");d.setAttribute("data-lang",v);d.lang=v;try{localStorage.setItem("futo-lang",v)}catch(x){}});})();`;

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ja" data-lang="ja" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: langScript }} />
      </head>
      <body>
        <header className="site">
          <a href="/" aria-label="ふとの紹介を見る / About Futo">
            <img src="/logo.png" alt="" width={36} />
            <h1>ふと</h1>
          </a>
          <div className="lang" role="group" aria-label="言語 / Language">
            <button type="button" data-set="ja">日本語</button>
            <button type="button" data-set="en">English</button>
          </div>
        </header>
        <main>{children}</main>
        <footer className="site">
          <a href="/"><Bi ja="ふとの紹介を見る" en="About Futo" /></a> ・ <a href="/support"><Bi ja="ふとを応援" en="Support Futo" /></a> ・ <a href="/privacy"><Bi ja="プライバシーポリシー" en="Privacy Policy" /></a>
        </footer>
      </body>
    </html>
  );
}
