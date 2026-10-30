import type { PublicShare } from "@/lib/shares";
import { AppBars, Donut, type Slice } from "./Charts";

// テーマの緑を中心にした、区別しやすい配色
const PALETTE = ["#196459", "#6fa898", "#e0b84a", "#b9c9c2"];

function dateRange(start: string, end: string, timeZone: string, withYear = false): string {
  const fmt = new Intl.DateTimeFormat("ja-JP", { ...(withYear ? { year: "numeric" as const } : {}), month: "numeric", day: "numeric", timeZone });
  return `${fmt.format(new Date(start))}〜${fmt.format(new Date(Date.parse(end) - 1000))}`;
}

/**
 * 共有の表示。表示名・アプリ名は、必ずテキストとして描画する（Reactが自動でエスケープする）。
 * 選ばれていない項目は、データ自体が届かないので、表示もされない。
 * グラフは凡例だけで読めるようにし、割合や注釈の文は出さない。
 */
export function ShareView({ share }: { share: PublicShare }) {
  const { stats } = share;
  const slices: { key: string; title: string; slices: Slice[] }[] = [];
  if (stats.counts) {
    slices.push({
      key: "counts",
      title: "ひと呼吸の結果",
      slices: [
        { label: "使いたい", value: stats.counts.wantsToUse, color: PALETTE[2] },
        { label: "やめておく", value: stats.counts.deferred, color: PALETTE[0] },
        { label: "途中でやめた", value: stats.counts.interrupted, color: PALETTE[3] },
      ],
    });
  }
  if (stats.purposes) {
    const p = stats.purposes;
    slices.push({
      key: "purposes",
      title: "使いたかった目的",
      slices: [
        { label: "連絡", value: p.contact, color: PALETTE[0] },
        { label: "調べもの", value: p.research, color: PALETTE[1] },
        { label: "気分転換", value: p.break, color: PALETTE[2] },
        { label: "なんとなく", value: p.noReason, color: PALETTE[3] },
      ],
    });
  }
  if (stats.feelings) {
    const f = stats.feelings;
    slices.push({
      key: "feelings",
      title: "使ったあとの感想",
      slices: [
        { label: "満足した", value: f.satisfied, color: PALETTE[0] },
        { label: "どちらでもない", value: f.neutral, color: PALETTE[3] },
        { label: "使いすぎかも", value: f.wishedLess, color: PALETTE[2] },
      ],
    });
  }
  const periodLabel = stats.period === "all" ? "全期間" : stats.period === "thisWeek" ? "今週" : "先週";
  return (
    <>
      <div className="card">
        <p className="who">{share.displayName ?? "匿名"}</p>
        <p className="muted">
          {periodLabel}（{dateRange(stats.periodStart, stats.periodEnd, stats.timezone, stats.period === "all")}）
        </p>
      </div>

      {slices.length > 0 && (
        <div className="card minis">
          {slices.map((s) => (
            <Donut key={s.key} title={s.title} slices={s.slices} />
          ))}
        </div>
      )}

      {stats.apps && stats.apps.length > 0 && (
        <div className="card">
          <h2>よく解除したアプリ</h2>
          <AppBars apps={stats.apps} color={PALETTE[0]} />
        </div>
      )}

      {stats.restriction && (
        <div className="card">
          <h2>制限の管理</h2>
          <div className="row"><span>一時停止</span><span>{stats.restriction.pauses}回</span></div>
          <div className="row"><span>制限の終了</span><span>{stats.restriction.ends}回</span></div>
        </div>
      )}

      {stats.phrase && <p className="phrase">{stats.phrase}</p>}

      <p className="muted" style={{ textAlign: "center" }}>
        {new Intl.DateTimeFormat("ja-JP", { dateStyle: "medium", timeStyle: "short", timeZone: stats.timezone }).format(new Date(share.createdAt))} に共有
      </p>
    </>
  );
}
