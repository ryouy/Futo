import Charts
import SwiftUI

/// 円グラフ（ドーナツ型）。件数は数字を並べず、凡例で見分ける。
struct PieCard: View {
    let title: String
    let slices: [Breakdown.Slice]
    var emptyText = "まだ記録がありません。"

    private var shown: [Breakdown.Slice] { slices.filter { $0.count > 0 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.medium))
            if shown.isEmpty {
                Text(emptyText).foregroundStyle(.secondary)
            } else {
                Chart(shown) { slice in
                    SectorMark(angle: .value("件数", slice.count), innerRadius: .ratio(0.55), angularInset: 2)
                        .foregroundStyle(by: .value("項目", slice.label))
                }
                .chartForegroundStyleScale(domain: slices.map(\.label),
                                           range: Array(Theme.chartColors.prefix(max(slices.count, 1))))
                .chartLegend(position: .bottom, alignment: .center, spacing: 12)
                .frame(height: 210)
                .accessibilityLabel(title)
                .accessibilityValue(shown.map { "\($0.label) \($0.count)件" }.joined(separator: "、"))
            }
        }
        .card()
    }
}
