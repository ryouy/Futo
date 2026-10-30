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

  it("匿名の表示と、途中経過の注記", () => {
    const html = renderToStaticMarkup(<ShareView share={{ ...base, displayName: null }} />);
    expect(html).toContain("匿名");
    expect(html).toContain("途中経過");
  });

  it("選ばれなかった項目の見出しは出ない", () => {
    const html = renderToStaticMarkup(<ShareView share={base} />);
    expect(html).toContain("選んだ回数");
    expect(html).not.toContain("使いたかった目的");
    expect(html).not.toContain("使ったあとの感想");
  });

  it("目的は、答えた件数を分母にし、答えなかった件数は含めない。分母0なら割合を出さない", () => {
    const withPurposes = { ...base, stats: { ...base.stats, purposes: { contact: 3, research: 1, break: 0, noReason: 0, unanswered: 6 } } };
    const html = renderToStaticMarkup(<ShareView share={withPurposes} />);
    expect(html).toContain("75%");
    expect(html).toContain("答えた4件");
    expect(html).toContain("答えなかった6件は含みません");
    const none = { ...base, stats: { ...base.stats, purposes: { contact: 0, research: 0, break: 0, noReason: 0, unanswered: 4 } } };
    const emptyHtml = renderToStaticMarkup(<ShareView share={none} />);
    expect(emptyHtml).not.toContain("NaN");
    // グラフの幅（style属性）は除き、表示される文字に割合が出ていないことを確認する
    expect(emptyHtml.replace(/ style="[^"]*"/g, "")).not.toContain("%");
    expect(emptyHtml).toContain("目的を答えた記録はまだありません");
  });

  it("満足感は、回答件数を併記する。回答0なら割合を出さない", () => {
    const html = renderToStaticMarkup(<ShareView share={{ ...base, stats: { ...base.stats, feelings: { satisfied: 1, neutral: 1, wishedLess: 0, answered: 2 } } }} />);
    expect(html).toContain("回答 2件");
    expect(html).toContain("50%");
    const empty = renderToStaticMarkup(<ShareView share={{ ...base, stats: { ...base.stats, feelings: { satisfied: 0, neutral: 0, wishedLess: 0, answered: 0 } } }} />);
    expect(empty).not.toContain("NaN");
    expect(empty).toContain("回答はまだありません");
  });

  it("実測していない使用時間や節約時間は、どこにも出ない", () => {
    const html = renderToStaticMarkup(<ShareView share={base} />);
    expect(html).not.toMatch(/使用時間|節約|連続|ランキング/);
  });

  it("グラフ：答えた目的があればドーナツを描き、数値も文字で読める。答えがなければ描かない", () => {
    const withPurposes = { ...base, stats: { ...base.stats, purposes: { contact: 3, research: 1, break: 0, noReason: 0, unanswered: 6 } } };
    const html = renderToStaticMarkup(<ShareView share={withPurposes} />);
    expect(html).toContain("<svg");
    expect(html).toContain("連絡");
    expect(html).toContain("3件");
    const none = { ...base, stats: { ...base.stats, purposes: { contact: 0, research: 0, break: 0, noReason: 0, unanswered: 4 } } };
    expect(renderToStaticMarkup(<ShareView share={none} />)).not.toContain("<svg");
  });
});
