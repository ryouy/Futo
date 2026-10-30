/** 共有ページ用の、軽いSVGグラフ（外部ライブラリなし）。数値は、隣の文字でも必ず読める。 */

export interface Slice {
  label: string;
  value: number;
  color: string;
}

const TAU = Math.PI * 2;

/** ドーナツ（円グラフ）。合計が0なら、何も描かない。 */
export function Donut({ slices, title }: { slices: Slice[]; title: string }) {
  const total = slices.reduce((sum, s) => sum + s.value, 0);
  if (total === 0) return null;
  const radius = 42;
  const circumference = TAU * radius;
  let offset = 0;
  return (
    <div className="chart">
      <svg viewBox="0 0 120 120" role="img" aria-label={title} width="132" height="132">
        <circle cx="60" cy="60" r={radius} fill="none" stroke="var(--soft)" strokeWidth="18" />
        {slices
          .filter((s) => s.value > 0)
          .map((s) => {
            const length = (s.value / total) * circumference;
            const circle = (
              <circle
                key={s.label}
                cx="60"
                cy="60"
                r={radius}
                fill="none"
                stroke={s.color}
                strokeWidth="18"
                strokeDasharray={`${length} ${circumference - length}`}
                strokeDashoffset={-offset}
                transform="rotate(-90 60 60)"
              />
            );
            offset += length;
            return circle;
          })}
        <text x="60" y="64" textAnchor="middle" fontSize="20" fontWeight="600" fill="var(--green)">
          {total}
        </text>
      </svg>
      <ul className="legend">
        {slices.map((s) => (
          <li key={s.label}>
            <span className="dot" style={{ background: s.color }} />
            {s.label}
            <span className="muted"> {s.value}件</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** 横の積み上げバー（回数の比較用）。 */
export function StackBar({ slices, title }: { slices: Slice[]; title: string }) {
  const total = slices.reduce((sum, s) => sum + s.value, 0);
  if (total === 0) return null;
  return (
    <div className="stack" role="img" aria-label={title}>
      {slices
        .filter((s) => s.value > 0)
        .map((s) => (
          <span key={s.label} style={{ width: `${(s.value / total) * 100}%`, background: s.color }} />
        ))}
    </div>
  );
}
