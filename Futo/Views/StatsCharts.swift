import Charts
import SwiftUI

/// 共有する統計の、グラフ表示用の形。送る前のプレビューと、フレンドから届いた統計の、どちらにも使う。
struct ChartStats {
    var counts: (wantsToUse: Int, deferred: Int, interrupted: Int)?
    var purposes: (contact: Int, research: Int, change: Int, noReason: Int, unanswered: Int)?
    var feelings: (satisfied: Int, neutral: Int, wishedLess: Int)?
    var restriction: RestrictionCounts?
    var phrase: String?
    var message: String?

    init(payload: SharePayload) {
        counts = payload.counts.map { ($0.wantsToUse, $0.deferred, $0.interrupted) }
        purposes = payload.purposes.map { ($0.contact, $0.research, $0.break, $0.noReason, $0.unanswered) }
        feelings = payload.feelings.map { ($0.satisfied, $0.neutral, $0.wishedLess) }
        phrase = payload.phraseId.flatMap(SharePhrase.init(rawValue:))?.text
        message = payload.message
        restriction = payload.restriction
    }

    init(snapshot: StatsSnapshotDTO) {
        counts = snapshot.counts.map { ($0.wantsToUse, $0.deferred, $0.interrupted) }
        purposes = snapshot.purposes.map { ($0.contact, $0.research, $0.break, $0.noReason, $0.unanswered) }
        feelings = snapshot.feelings.map { ($0.satisfied, $0.neutral, $0.wishedLess) }
        phrase = snapshot.phrase
        message = snapshot.message
        restriction = snapshot.restriction
    }
}

private struct ChartSlice: Identifiable {
    var label: String
    var count: Int
    var color: Color
    var id: String { label }
}

/// 選んだ項目だけを、カードのグラフで見せる。数字は凡例にも出す。
struct StatsChartsView: View {
    let stats: ChartStats

    var body: some View {
        VStack(spacing: 12) {
            if let message = stats.message {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "quote.opening").foregroundStyle(Theme.accentText).font(.footnote)
                    Text(message).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14).card()
                .accessibilityElement(children: .combine)
            }
            if let c = stats.counts { countsCard(c) }
            if let p = stats.purposes { purposesCard(p) }
            if let f = stats.feelings { feelingsCard(f) }
            if let r = stats.restriction { restrictionCard(r) }
            if let phrase = stats.phrase {
                Text(phrase).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity).padding(14).card()
            }
        }
    }

    private var palette: [Color] { Theme.chartColors }

    private func countsCard(_ c: (wantsToUse: Int, deferred: Int, interrupted: Int)) -> some View {
        let slices = [
            ChartSlice(label: tr("使いたい"), count: c.wantsToUse, color: palette[2]),
            ChartSlice(label: tr("やめておく"), count: c.deferred, color: palette[0]),
            ChartSlice(label: tr("中断"), count: c.interrupted, color: palette[3]),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("ひと呼吸の結果")).font(.subheadline.weight(.medium))
            if slices.allSatisfy({ $0.count == 0 }) {
                Text(tr("まだ記録がありません")).font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(slices.filter { $0.count > 0 }) { slice in
                    BarMark(x: .value(tr("件数"), slice.count)).foregroundStyle(slice.color)
                        .cornerRadius(6)
                }
                .chartXAxis(.hidden)
                .frame(height: 26)
                .accessibilityLabel(tr("ひと呼吸の結果"))
                .accessibilityValue(slices.map { "\($0.label) \($0.count)" }.joined(separator: " / "))
                WrapHStack(spacing: 16, lineSpacing: 6) {
                    ForEach(slices) { slice in legend(slice) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// 制限の管理：一時停止と終了の回数。
    private func restrictionCard(_ r: RestrictionCounts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("制限の管理")).font(.subheadline.weight(.medium))
            HStack {
                Text(tr("一時停止"))
                Spacer()
                Text(tr("{0}回", "\(r.pauses)")).monospacedDigit().foregroundStyle(.secondary)
            }
            HStack {
                Text(tr("制限の終了"))
                Spacer()
                Text(tr("{0}回", "\(r.ends)")).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func purposesCard(_ p: (contact: Int, research: Int, change: Int, noReason: Int, unanswered: Int)) -> some View {
        donut(title: tr("使いたかった目的"), slices: [
            ChartSlice(label: tr("連絡"), count: p.contact, color: palette[0]),
            ChartSlice(label: tr("調べもの"), count: p.research, color: palette[1]),
            ChartSlice(label: tr("気分転換"), count: p.change, color: palette[2]),
            ChartSlice(label: tr("なんとなく"), count: p.noReason, color: palette[3]),
        ], note: nil)
    }

    private func feelingsCard(_ f: (satisfied: Int, neutral: Int, wishedLess: Int)) -> some View {
        donut(title: tr("使ったあとの感想"), slices: [
            ChartSlice(label: tr("満足した"), count: f.satisfied, color: palette[0]),
            ChartSlice(label: tr("どちらでもない"), count: f.neutral, color: palette[3]),
            ChartSlice(label: tr("使いすぎかも"), count: f.wishedLess, color: palette[2]),
        ], note: nil)
    }

    private func donut(title: String, slices: [ChartSlice], note: String?) -> some View {
        let total = slices.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium))
            if total == 0 {
                Text(tr("まだ記録がありません")).font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 20) {
                    Chart(slices.filter { $0.count > 0 }) { slice in
                        SectorMark(angle: .value(tr("件数"), slice.count), innerRadius: .ratio(0.58), angularInset: 2)
                            .foregroundStyle(slice.color)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 124, height: 124)
                    .overlay {
                        VStack(spacing: 0) {
                            Text("\(total)").font(.title3.weight(.semibold).monospacedDigit())
                            Text(tr("件")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
                    .accessibilityValue(slices.map { "\($0.label) \($0.count)" }.joined(separator: " / "))
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(slices) { slice in legend(slice, total: total) }
                    }
                    Spacer(minLength: 0)
                }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func legend(_ slice: ChartSlice, total: Int? = nil) -> some View {
        let value = total.map { total in total > 0 ? "\(slice.count)（\(Int((Double(slice.count) / Double(total) * 100).rounded()))%）" : "\(slice.count)" } ?? "\(slice.count)"
        // 1行に収まれば1行。英語のように長いときは、名前の下に数を置く（名前も、折り返して、省略しない）
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                Circle().fill(slice.color).frame(width: 8, height: 8)
                Text(slice.label).font(.caption).lineLimit(1)
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 6) {
                Circle().fill(slice.color).frame(width: 8, height: 8).padding(.top, 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(slice.label).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
