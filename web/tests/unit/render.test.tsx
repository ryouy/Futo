import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { ShareView } from "@/components/ShareView";
import type { PublicShare } from "@/lib/shares";

const base: PublicShare = {
  displayName: "ふつうの名前",
  createdAt: "2027-01-14T03:00:00.000Z",
  expiresAt: "2027-01-21T03:00:00.000Z",
  stats: {
    period: "thisWeek",
    periodStart: "2027-01-10T19:00:00.000Z",
    periodEnd: "2027-01-17T19:00:00.000Z",
    timezone: "Asia/Tokyo",
    isPartial: true,
    counts: { wantsToUse: 5, deferred: 3, interrupted: 1 },
  },
};

describe("Web共有ページの表示", () => {
  it("表示名にHTMLが含まれても、実行されない（エスケープされる）", () => {
    const html = renderToStaticMarkup(<ShareView share={{ ...base, displayName: "<script>alert(1)</script><img src=x onerror=alert(2)>" }} />);
    expect(html).not.toContain("<script>");
    expect(html).not.toContain("<img src=x");
    expect(html).toContain("&lt;script&gt;");
  });

  it("匿名の表示。途中経過・割合・件数の文章は出さない（凡例だけ）", () => {
    const html = renderToStaticMarkup(<ShareView share={{ ...base, displayName: null, stats: { ...base.stats, purposes: { contact: 13, research: 14, break: 10, noReason: 8, unanswered: 2 } } }} />);
    expect(html).toContain("匿名");
    expect(html).not.toContain("途中経過");
    expect(html).not.toContain("%");
    expect(html).not.toContain("件（");
    expect(html).not.toContain("含みません");
    expect(html).not.toContain("内訳です");
    expect(html).toContain("調べもの"); // 凡例には名前が出る
  });

  it("選ばれなかった項目の見出しは出ない。見出しは短い言葉", () => {
    const html = renderToStaticMarkup(<ShareView share={base} />);
    expect(html).toContain("ひと呼吸の結果");
    expect(html).not.toContain("選んだ回数");
    expect(html).not.toContain("使いたかった目的");
    expect(html).not.toContain("使ったあとの感想");
    expect(html).not.toContain("よく解除したアプリ");
  });

  it("選んだ3つのグラフは、1枚のカードにまとまる", () => {
    const html = renderToStaticMarkup(<ShareView share={{ ...base, stats: { ...base.stats, purposes: { contact: 3, research: 1, break: 0, noReason: 0, unanswered: 6 }, feelings: { satisfied: 1, neutral: 1, wishedLess: 0, answered: 2 } } }} />);
    expect(html.match(/class="card minis"/g)?.length).toBe(1);
    expect(html.match(/<svg/g)?.length).toBe(3);
    expect(html).toContain("使いたかった目的");
    expect(html).toContain("使ったあとの感想");
    // 数値は、グラフの読み上げ用の説明にだけ入る
    expect(html).toContain("連絡 3件");
  });

  it("アプリ名：選んだときだけ出る。名前はエスケープされる", () => {
    const html = renderToStaticMarkup(<ShareView share={{ ...base, stats: { ...base.stats, apps: [{ name: "<b>SNS</b>", count: 7 }, { name: "動画", count: 3 }] } }} />);
    expect(html).toContain("よく解除したアプリ");
    expect(html).toContain("&lt;b&gt;SNS&lt;/b&gt;");
    expect(html).not.toContain("<b>SNS</b>");
    expect(html).toContain("動画");
  });

  it("制限の管理：選んだときだけ、一時停止と終了の回数が出る", () => {
    expect(renderToStaticMarkup(<ShareView share={base} />)).not.toContain("制限の管理");
    const html = renderToStaticMarkup(<ShareView share={{ ...base, stats: { ...base.stats, restriction: { pauses: 2, ends: 1 } } }} />);
    expect(html).toContain("制限の管理");
    expect(html).toContain("一時停止");
    expect(html).toContain("2回");
    expect(html).toContain("制限の終了");
  });

  it("実測していない使用時間や節約時間は、どこにも出ない", () => {
    const html = renderToStaticMarkup(<ShareView share={{ ...base, stats: { ...base.stats, purposes: { contact: 1, research: 1, break: 1, noReason: 1, unanswered: 0 }, feelings: { satisfied: 1, neutral: 1, wishedLess: 1, answered: 3 } } }} />);
    expect(html).not.toMatch(/使用時間|節約|スクリーンタイム/);
  });

  it("答えのない項目は、グラフを描かない", () => {
    const none = { ...base, stats: { ...base.stats, counts: undefined, purposes: { contact: 0, research: 0, break: 0, noReason: 0, unanswered: 4 } } };
    expect(renderToStaticMarkup(<ShareView share={none} />)).not.toContain("<svg");
  });
});
