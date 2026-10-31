import type { PublicShare } from "@/lib/shares";
import { Bi, type Bilingual } from "./Bi";
import { AppBars, Donut, type Slice } from "./Charts";

const b = (ja: string, en: string): Bilingual => ({ ja, en });

/** 定型のひとことの英訳（保存された日本語の文から引く。「。」の有無は問わない）。 */
const PHRASE_EN: Record<string, string> = {
  "こんな感じでした": "This is how it went",
  "ひと呼吸の記録を、少しだけ共有します": "Sharing a little of my breath records",
  "ふと、立ち止まった記録です": "A record of pausing, just for a moment",
};
const phraseEn = (text: string) => PHRASE_EN[text.replace(/。$/, "")];

// テーマの緑を中心にした、区別しやすい配色
const PALETTE = ["#196459", "#6fa898", "#e0b84a", "#b9c9c2"];

function dateRange(start: string, end: string, timeZone: string): string {
  const fmt = new Intl.DateTimeFormat("sv-SE", { year: "numeric", month: "2-digit", day: "2-digit", timeZone });
  return `${fmt.format(new Date(start))}〜${fmt.format(new Date(Date.parse(end) - 1000))}`.replaceAll("-", "/");
}

/**
 * 共有の表示。表示名・アプリ名は、必ずテキストとして描画する（Reactが自動でエスケープする）。
 * 選ばれていない項目は、データ自体が届かないので、表示もされない。
 * グラフは凡例だけで読めるようにし、割合や注釈の文は出さない。
 */
export function ShareView({ share }: { share: PublicShare }) {
  const { stats } = share;
  const slices: { key: string; title: Bilingual; slices: Slice[] }[] = [];
  if (stats.counts) {
    slices.push({
      key: "counts",
      title: b("ひと呼吸の結果", "Breath results"),
      slices: [
        { label: b("使いたい", "Wanted to use"), value: stats.counts.wantsToUse, color: PALETTE[2] },
        { label: b("やめておく", "Held off"), value: stats.counts.deferred, color: PALETTE[0] },
        { label: b("途中でやめた", "Stopped midway"), value: stats.counts.interrupted, color: PALETTE[3] },
      ],
    });
  }
  if (stats.purposes) {
    const p = stats.purposes;
    slices.push({
      key: "purposes",
      title: b("使いたかった目的", "Purpose"),
      slices: [
        { label: b("連絡", "Contact"), value: p.contact, color: PALETTE[0] },
        { label: b("調べもの", "Look-up"), value: p.research, color: PALETTE[1] },
        { label: b("気分転換", "Break"), value: p.break, color: PALETTE[2] },
        { label: b("なんとなく", "No reason"), value: p.noReason, color: PALETTE[3] },
      ],
    });
  }
  if (stats.feelings) {
    const f = stats.feelings;
    slices.push({
      key: "feelings",
      title: b("使ったあとの感想", "How it felt"),
      slices: [
        { label: b("満足した", "Satisfied"), value: f.satisfied, color: PALETTE[0] },
        { label: b("どちらでもない", "Neutral"), value: f.neutral, color: PALETTE[3] },
        { label: b("使いすぎかも", "Too much?"), value: f.wishedLess, color: PALETTE[2] },
      ],
    });
  }
  const periodLabel = stats.period === "all" ? b("全期間", "All time") : stats.period === "thisWeek" ? b("今週", "This week") : b("先週", "Last week");
  return (
    <>
      <div className="card">
        <p className="who">{share.displayName ?? <Bi ja="匿名" en="Anonymous" />}</p>
        <p className="muted">
          <Bi ja={periodLabel.ja} en={periodLabel.en} />（{dateRange(stats.periodStart, stats.periodEnd, stats.timezone)}）
        </p>
      </div>

      {slices.length > 0 && (
        <div className="card minis" style={{ gridTemplateColumns: `repeat(${Math.min(slices.length, 3)}, minmax(0, 1fr))` }}>
          {slices.map((s) => (
            <Donut key={s.key} title={s.title} slices={s.slices} />
          ))}
        </div>
      )}

      {stats.apps && stats.apps.length > 0 && (
        <div className="card">
          <h2><Bi ja="よく解除したアプリ" en="Most unlocked apps" /></h2>
          <AppBars apps={stats.apps} color={PALETTE[0]} />
        </div>
      )}

      {stats.restriction && (
        <div className="card">
          <h2><Bi ja="制限の管理" en="Lock management" /></h2>
          <div className="row"><span><Bi ja="一時停止" en="Pauses" /></span><span><Bi ja={`${stats.restriction.pauses}回`} en={`${stats.restriction.pauses}`} /></span></div>
          <div className="row"><span><Bi ja="制限の終了" en="Lock ended" /></span><span><Bi ja={`${stats.restriction.ends}回`} en={`${stats.restriction.ends}`} /></span></div>
        </div>
      )}

      {stats.phrase && <p className="phrase"><Bi ja={stats.phrase.replace(/。$/, "")} en={phraseEn(stats.phrase) ?? stats.phrase.replace(/。$/, "")} /></p>}
      {stats.message && <p className="phrase">{stats.message}</p>}

      <p className="muted" style={{ textAlign: "center" }}>
        {new Intl.DateTimeFormat("sv-SE", { dateStyle: "short", timeStyle: "short", timeZone: stats.timezone }).format(new Date(share.createdAt)).replaceAll("-", "/")}{" "}
        <Bi ja="に共有" en="shared" />
      </p>
    </>
  );
}
