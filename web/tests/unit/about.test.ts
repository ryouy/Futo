import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { makeAbout } from "@/lib/aboutPage";

const read = (name: string) => readFileSync(new URL(`../../public/${name}`, import.meta.url), "utf8");

describe("アプリ用の紹介ページ（/about）", () => {
  it("課金のページ（/support）へのリンクが、どこにも無い", () => {
    expect(read("about.html")).not.toContain("/support");
  });

  it("トップ（intro.html）から作った内容と一致している（intro.html を変えたら、npm run make:about を実行する）", () => {
    expect(read("about.html")).toBe(makeAbout(read("intro.html")));
  });

  it("Web 課金は廃止した：トップにも、購入のページ・購入の入口が無い", () => {
    const intro = read("intro.html");
    expect(intro).not.toContain('href="/support"');
    expect(intro).not.toContain("/api/billing");
    expect(intro).not.toContain("月額");
  });

  it("プライバシーポリシーは、/about に戻れる形で開く。検索には出さない", () => {
    const about = read("about.html");
    expect(about).toContain('href="/privacy?from=about"');
    expect(about).toContain('<meta name="robots" content="noindex">');
    expect(read("privacy.html")).toContain("from=about");
  });
});
