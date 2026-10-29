import SwiftData
import SwiftUI

/// 「今週」の傾向。記録された操作だけで作る。
struct InsightsView: View {
    let mode: AppMode
    @Query private var sessions: [Session]

    private var calendar: LogicalCalendar { LogicalCalendar() }

    var body: some View {
        let insights = WeeklyInsights.make(sessions: sessions, mode: mode, calendar: calendar, now: Date())
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(weekText).font(.footnote).foregroundStyle(.secondary)

                if insights.total == 0 {
                    Text("今週の記録はまだありません。")
                        .card()
                } else {
                    countsCard(insights)
                    if insights.answeredPurposes + insights.purposeSkipped > 0 { purposeCard(insights) }
                    reflectionCard(insights)
                    bandCard(insights)
                    if let previous = insights.previousTotal {
                        Text("先週は\(previous)件、今週は\(insights.total)件の記録がありました。記録の件数は日によって違うため、増減の良し悪しは判断しません。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var weekText: String {
        let week = calendar.weekInterval(containing: Date())
        let last = week.end.addingTimeInterval(-86_400)
        let format = Date.FormatStyle().month().day()
        return "今週（\(week.start.formatted(format))〜\(last.formatted(format))）"
    }

    // MARK: カード

    private func countsCard(_ w: WeeklyInsights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row("ひと呼吸", w.total)
            row("「やめておく」を選んだ", w.deferred)
            row("「使いたい」を選んだ", w.wantsToUse)
            row("使ったあとの感想に答えた", w.answeredReflections)
            if w.unlockStarted > 0 { row("一時解除を始めた", w.unlockStarted) }
            Text("「使いたい」は、対象アプリを開こうとした回数ではありません。一時解除を始めた回数は、実際に使ったかどうかを表しません。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .card()
    }

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text("\(value)").monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func purposeCard(_ w: WeeklyInsights) -> some View {
        var slices = Purpose.allCases.map { Breakdown.Slice(label: $0.label, count: w.purposeCounts[$0] ?? 0) }
        slices.append(Breakdown.Slice(label: Breakdown.noAnswer, count: w.purposeSkipped))
        return PieCard(title: "選んだ目的", slices: slices,
                       footnote: "答えなかった分も含めた内訳です。")
    }

    private func reflectionCard(_ w: WeeklyInsights) -> some View {
        let slices = [Reflection.satisfied, .neutral, .wishedLess].map {
            Breakdown.Slice(label: $0.label, count: w.reflectionCounts[$0] ?? 0)
        }
        return PieCard(title: "使ったあとの感想", slices: slices,
                       emptyText: "今週は、まだ回答がありません。",
                       footnote: w.answeredReflections == 0 ? nil
                           : "回答 \(w.answeredReflections)件の内訳です。「答えない」は含みません。")
    }

    private func bandCard(_ w: WeeklyInsights) -> some View {
        let items = TimeBand.allCases.map { ($0.label, w.bandCounts[$0] ?? 0) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("記録が多い時間帯").font(.subheadline.weight(.medium))
            bars(items)
            Text("ひと呼吸を始めた時刻の記録です。実際のスマホの使用時間の分布ではありません。")
                .font(.caption).foregroundStyle(.secondary)
                .lineSpacing(3)
        }
        .card()
    }

    /// 少数のシンプルな横棒。数と文字を必ず併記する。
    private func bars(_ items: [(String, Int)]) -> some View {
        let maxValue = max(items.map(\.1).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 10) {
                    Text(item.0).font(.footnote).frame(width: 118, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.accent.opacity(item.1 == 0 ? 0.12 : 0.85))
                            .frame(width: max(8, proxy.size.width * CGFloat(item.1) / CGFloat(maxValue)))
                    }
                    .frame(height: 10)
                    Text("\(item.1)").font(.footnote.monospacedDigit()).frame(width: 24, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// 履歴シートの中身。「今週」と「履歴」を切り替える。
struct RecordsView: View {
    let mode: AppMode
    @State private var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("表示", selection: $tab) {
                Text("今週").tag(0)
                Text("履歴").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            if tab == 0 { InsightsView(mode: mode) } else { HistoryView(mode: mode) }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("記録")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { GraphView(mode: mode) } label: { Label("グラフ", systemImage: "chart.bar") }
            }
        }
    }
}
