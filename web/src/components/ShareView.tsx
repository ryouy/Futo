import type { PublicShare } from "@/lib/shares";
import { Donut, StackBar, type Slice } from "./Charts";
import { ReportButton } from "./ReportButton";

// テーマの緑を中心にした、区別しやすい配色
const PALETTE = ["#196459", "#6fa898", "#e0b84a", "#b9c9c2"];

const PURPOSES: [keyof NonNullable<PublicShare["stats"]["purposes"]>, string][] = [
  ["contact", "連絡"],
  ["research", "調べもの"],
  ["break", "気分転換"],
  ["noReason", "なんとなく"],
];
const FEELINGS: [keyof NonNullable<PublicShare["stats"]["feelings"]>, string][] = [
  ["satisfied", "満足した"],
  ["neutral", "どちらでもない"],
  ["wishedLess", "使いすぎかも"],
];

const percent = (part: number, whole: number) => `${Math.round((part / whole) * 100)}%`;

function dateRange(start: string, end: string, timeZone: string): string {
  const fmt = new Intl.DateTimeFormat("ja-JP", { month: "numeric", day: "numeric", timeZone });
  return `${fmt.format(new Date(start))}〜${fmt.format(new Date(Date.parse(end) - 1000))}`;
}

/**
 * 共有の表示。表示名は、必ずテキストとして描画する（Reactが自動でエスケープする）。
 * 選ばれていない項目は、データ自体が届かないので、表示もされない。
 */
export function ShareView({ share, token }: { share: PublicShare; token?: string }) {
  const { stats } = share;
  const answeredPurposes = stats.purposes ? PURPOSES.reduce((sum, [key]) => sum + (stats.purposes?.[key] ?? 0), 0) : 0;
  return (
    <>
      <div className="card">
        <p className="who">{share.displayName ?? "匿名"}</p>
        <p className="muted">
          {stats.period === "thisWeek" ? "今週" : "先週"}（{dateRange(stats.periodStart, stats.periodEnd, stats.timezone)}）
        </p>
        {stats.isPartial && <p className="notice">今週は、共有した時点までの途中経過です。</p>}
      </div>

      {stats.counts && (
        <div className="card">
          <h2>選んだ回数</h2>
          <StackBar
            title="使いたい・やめておく・途中でやめたの割合"
            slices={[
              { label: "使いたい", value: stats.counts.wantsToUse, color: PALETTE[2] },
              { label: "やめておく", value: stats.counts.deferred, color: PALETTE[0] },
              { label: "途中でやめた", value: stats.counts.interrupted, color: PALETTE[3] },
            ]}
          />
          <div className="row"><span>使いたい</span><span>{stats.counts.wantsToUse}</span></div>
          <div className="row"><span>やめておく</span><span>{stats.counts.deferred}</span></div>
          <div className="row"><span>途中でやめた</span><span>{stats.counts.interrupted}</span></div>
          <p className="muted">「使いたい」は、対象のアプリを開こうとした回数ではありません。</p>
        </div>
      )}

      {stats.purposes && (
        <div className="card">
          <h2>使いたかった目的</h2>
          {answeredPurposes === 0 ? (
            <p className="muted">目的を答えた記録はまだありません。</p>
          ) : (
            <>
              <Donut title="使いたかった目的の内訳" slices={PURPOSES.map(([key, label], i): Slice => ({ label, value: stats.purposes?.[key] ?? 0, color: PALETTE[i] }))} />
              {PURPOSES.map(([key, label]) => (
              <div className="row" key={key}>
                <span>{label}</span>
                <span>{stats.purposes?.[key]}件（{percent(stats.purposes?.[key] ?? 0, answeredPurposes)}）</span>
              </div>
              ))}
            </>
          )}
          <p className="muted">目的を答えた{answeredPurposes}件の内訳です。答えなかった{stats.purposes.unanswered}件は含みません。</p>
        </div>
      )}

      {stats.feelings && (
        <div className="card">
          <h2>使ったあとの感想</h2>
          {stats.feelings.answered === 0 ? (
            <p className="muted">回答はまだありません。</p>
          ) : (
            <>
              <Donut title="使ったあとの感想の内訳" slices={FEELINGS.map(([key, label], i): Slice => ({ label, value: stats.feelings?.[key] ?? 0, color: [PALETTE[0], PALETTE[3], PALETTE[2]][i] }))} />
              {FEELINGS.map(([key, label]) => (
              <div className="row" key={key}>
                <span>{label}</span>
                <span>{stats.feelings?.[key]}件（{percent(stats.feelings?.[key] ?? 0, stats.feelings?.answered ?? 1)}）</span>
              </div>
              ))}
            </>
          )}
          <p className="muted">回答 {stats.feelings.answered}件の内訳です。</p>
        </div>
      )}

      {stats.phrase && <p className="phrase">{stats.phrase}</p>}

      <p className="muted" style={{ textAlign: "center" }}>
        共有した日時：{new Intl.DateTimeFormat("ja-JP", { dateStyle: "medium", timeStyle: "short", timeZone: stats.timezone }).format(new Date(share.createdAt))}
        <br />
        端末の中の記録から、本人が選んだ項目だけを集計したものです。
      </p>
      {token && <ReportButton token={token} />}
    </>
  );
}
