/** 共有ページ用の、軽いSVGグラフ（外部ライブラリなし）。凡例は名前だけ。数値は、読み上げ用の説明に入れる。 */

import { Bi, type Bilingual } from "./Bi";

export interface Slice {
  label: Bilingual;
  value: number;
  color: string;
}

const TAU = Math.PI * 2;

/** 小さなドーナツ＋凡例（名前だけ）。合計が0なら、何も描かない。 */
export function Donut({ slices, title }: { slices: Slice[]; title: Bilingual }) {
  const total = slices.reduce((sum, s) => sum + s.value, 0);
  if (total === 0) return null;
  const radius = 40;
  const circumference = TAU * radius;
  let offset = 0;
  const description = `${title.ja} / ${title.en}：${slices.filter((s) => s.value > 0).map((s) => `${s.label.ja} ${s.value}`).join(", ")}`;
  return (
    <div className="mini">
      <h3><span><Bi ja={title.ja} en={title.en} /></span></h3>
      <svg viewBox="0 0 120 120" role="img" aria-label={description} width="104" height="104">
        <circle cx="60" cy="60" r={radius} fill="none" stroke="var(--soft)" strokeWidth="20" />
        {slices
          .filter((s) => s.value > 0)
          .map((s) => {
            const length = (s.value / total) * circumference;
            const circle = (
              <circle
                key={s.label.ja}
                cx="60"
                cy="60"
                r={radius}
                fill="none"
                stroke={s.color}
                strokeWidth="20"
                strokeDasharray={`${length} ${circumference - length}`}
                strokeDashoffset={-offset}
                transform="rotate(-90 60 60)"
              />
            );
            offset += length;
            return circle;
          })}
      </svg>
      <ul className="legend">
        {slices.map((s) => (
          <li key={s.label.ja}>
            <span className="dot" style={{ background: s.color }} />
            <Bi ja={s.label.ja} en={s.label.en} />
          </li>
        ))}
      </ul>
    </div>
  );
}

/** よく解除したアプリ：名前と、横棒。 */
export function AppBars({ apps, color }: { apps: { name: string; count: number }[]; color: string }) {
  const max = Math.max(...apps.map((a) => a.count), 1);
  return (
    <ul className="appbars">
      {apps.map((a) => (
        <li key={a.name}>
          <span className="appname">{a.name}</span>
          <span className="bar" aria-hidden="true">
            <span style={{ width: `${Math.max(6, (a.count / max) * 100)}%`, background: color }} />
          </span>
          <span className="n">{a.count}</span>
        </li>
      ))}
    </ul>
  );
}
