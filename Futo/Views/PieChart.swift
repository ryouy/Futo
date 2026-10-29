import Charts
import SwiftUI

/// 円グラフ（ドーナツ型）。件数は数字を並べず、凡例で見分ける。
struct PieCard: View {
    let title: String
    let slices: [Breakdown.Slice]
    var emptyText = tr("まだ記録がありません。")

    private var shown: [Breakdown.Slice] { slices.filter { $0.count > 0 } }

    private func color(for slice: Breakdown.Slice) -> Color {
        let colors = Theme.chartColors
        let index = slices.firstIndex(where: { $0.label == slice.label }) ?? 0
        return colors[index % colors.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium))
            if shown.isEmpty {
                Text(emptyText).font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .center, spacing: 20) {
                    Chart(shown) { slice in
                        SectorMark(angle: .value(tr("件数"), slice.count), innerRadius: .ratio(0.55), angularInset: 2)
                            .foregroundStyle(color(for: slice))
                    }
                    .chartLegend(.hidden)
                    .frame(width: 120, height: 120)
                    .accessibilityLabel(title)
                    .accessibilityValue(shown.map { tr("{0} {1}件", "\($0.label)", "\($0.count)") }.joined(separator: tr("、")))

                    // 凡例は小さく、グラフの横に縦に並べる。
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(shown) { slice in
                            HStack(spacing: 6) {
                                Circle().fill(color(for: slice)).frame(width: 8, height: 8)
                                Text(slice.label).font(.caption).oneLine(0.8)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .card()
    }
}
