import type { PublicShare } from "@/lib/shares";
import { Bi, type Bilingual } from "./Bi";
import { Donut, type Slice } from "./Charts";

const b = (ja: string, en: string): Bilingual => ({ ja, en });

/** 定型のひとことの英訳（保存された日本語の文から引く。「。」の有無は問わない）。 */
const PHRASE_EN: Record<string, string> = {
  "こんな感じでした": "This is how it went",
  "ひと呼吸の記録を、少しだけ共有します": "Sharing a little of my breath records",
  "ふと、立ち止まった記録です": "A record of pausing, just for a moment",
};
const phraseEn = (text: string) => PHRASE_EN[text.replace(/。$/, "")];

// テーマの緑と、はっきり違う色（同じ色の濃淡だけでは、見分けにくい）
const C = { teal: "#196459", amber: "#e0b84a", coral: "#d98a63", sky: "#6fa6c8", stone: "#b9c9c2" };

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
        { label: b("使いたい", "Use it"), value: stats.counts.wantsToUse, color: C.amber },
        { label: b("やめておく", "Held off"), value: stats.counts.deferred, color: C.teal },
        { label: b("途中でやめた", "Stopped"), value: stats.counts.interrupted, color: C.stone },
      ],
    });
  }
  if (stats.purposes) {
    const p = stats.purposes;
    slices.push({
      key: "purposes",
      title: b("使いたかった目的", "Purpose"),
      slices: [
        { label: b("連絡", "Contact"), value: p.contact, color: C.teal },
        { label: b("調べもの", "Look-up"), value: p.research, color: C.sky },
        { label: b("気分転換", "Break"), value: p.break, color: C.amber },
        { label: b("なんとなく", "No reason"), value: p.noReason, color: C.stone },
      ],
    });
  }
  if (stats.feelings) {
    const f = stats.feelings;
    slices.push({
      key: "feelings",
      title: b("使ったあとの感想", "How it felt"),
      slices: [
        { label: b("満足した", "Satisfied"), value: f.satisfied, color: C.teal },
        { label: b("どちらでもない", "Neutral"), value: f.neutral, color: C.stone },
        { label: b("使いすぎかも", "Too much?"), value: f.wishedLess, color: C.coral },
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
