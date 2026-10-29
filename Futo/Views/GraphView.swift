import Charts
import SwiftData
import SwiftUI

/// この7日間のグラフ。結果の回数と、制限を解除していた時間。使用時間は取得していないので出さない。
struct GraphView: View {
    let mode: AppMode
    @Query private var sessions: [Session]

    private struct Point: Identifiable {
        var id: String { "\(day)-\(kind)" }
        var day: String
        var kind: String
        var count: Int
    }

    private var series: [DayStat] {
        DailySeries.make(sessions: sessions, mode: mode, calendar: LogicalCalendar(), now: Date(), days: 7)
    }

    private var points: [Point] {
        series.flatMap { stat in
            [Point(day: stat.label, kind: "やめた", count: stat.deferred),
             Point(day: stat.label, kind: "解除した・使いたい", count: stat.wantsToUse),
             Point(day: stat.label, kind: "途中でやめた", count: stat.interrupted)]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("この7日間").font(.footnote).foregroundStyle(.secondary)
                if series.allSatisfy({ $0.total == 0 }) {
                    Text("まだ記録がありません。").card()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ひと呼吸の結果（回数）").font(.subheadline.weight(.medium))
                        Chart(points) { point in
                            BarMark(x: .value("日", point.day), y: .value("回数", point.count))
                                .foregroundStyle(by: .value("結果", point.kind))
                        }
                        .chartForegroundStyleScale([
                            "やめた": Theme.accent,
                            "解除した・使いたい": Theme.accent.opacity(0.45),
                            "途中でやめた": Color.secondary.opacity(0.35),
                        ])
                        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                        .frame(height: 200)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("制限を解除していた時間（分）").font(.subheadline.weight(.medium))
                        Chart(series) { stat in
                            BarMark(x: .value("日", stat.label), y: .value("分", stat.unlockSeconds / 60))
                                .foregroundStyle(Theme.accent)
                        }
                        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
                        .frame(height: 140)
                        Text("使った時間ではなく、解除していた時間です。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .card()
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("グラフ")
        .navigationBarTitleDisplayMode(.inline)
    }
}
