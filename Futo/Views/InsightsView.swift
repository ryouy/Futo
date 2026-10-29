import SwiftData
import SwiftUI

/// 記録の画面。「今週／今月／すべて」を切り替えて、集計・円グラフ・記録の一覧を1画面で見る。
struct RecordsView: View {
    let mode: AppMode
    @State private var period: InsightPeriod = .week
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    var body: some View {
        let calendar = LogicalCalendar()
        let now = Date()
        let insights = PeriodInsights.make(sessions: sessions, mode: mode, period: period, calendar: calendar, now: now)
        let interval = period.interval(calendar: calendar, now: now)
        let finished = PeriodInsights.records(sessions: sessions, mode: mode, interval: interval).filter { !$0.phase.isOpen }
        let breakdown = Breakdown.make(sessions: sessions, mode: mode, interval: interval)

        VStack(spacing: 0) {
            Picker(tr("期間"), selection: $period) {
                ForEach(InsightPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            let today = DailyCounts.today(sessions: sessions, mode: mode)
            Text(tr("今日　やめた {0}　使いたかった {1}", "\(today.deferred)", "\(today.wantsToUse)"))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if insights.total == 0 {
                        Text(tr("この期間の記録はまだありません。")).foregroundStyle(.secondary).card()
                    } else {
                        countsCard(insights)
                        PieCard(title: tr("目的"), slices: breakdown.purposes)
                        if insights.answeredReflections > 0 {
                            PieCard(title: tr("感想"), slices: breakdown.reflections)
                        }
                        bandCard(insights)
                        recordsCard(finished)
                    }
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.3), value: period)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tr("記録"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: カード

    private func countsCard(_ w: PeriodInsights) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row(tr("ひと呼吸"), "\(w.total)")
            row(tr("やめておく"), "\(w.deferred)")
            row(tr("使いたい"), "\(w.wantsToUse)")
            if w.answeredReflections > 0 { row(tr("感想に答えた"), "\(w.answeredReflections)") }
            if w.unlockStarted > 0 {
                row(tr("解除した"), w.unlockSeconds >= 60 ? tr("{0}回・約{1}分", "\(w.unlockStarted)", "\(Int((w.unlockSeconds / 60).rounded()))") : tr("{0}回", "\(w.unlockStarted)"))
            }
        }
        .card()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func bandCard(_ w: PeriodInsights) -> some View {
        let items = TimeBand.allCases.map { ($0.label, w.bandCounts[$0] ?? 0) }
        let maxValue = max(items.map(\.1).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            Text(tr("時間帯")).font(.subheadline.weight(.medium))
            ForEach(items, id: \.0) { item in
                HStack(spacing: 10) {
                    Text(item.0).font(.footnote).frame(width: 44, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Theme.accent.opacity(item.1 == 0 ? 0.12 : 0.85))
                            .frame(width: max(8, proxy.size.width * CGFloat(item.1) / CGFloat(maxValue)))
                    }
                    .frame(height: 10)
                    Text("\(item.1)").font(.footnote.monospacedDigit()).frame(width: 28, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private func recordsCard(_ records: [Session]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(tr("記録")).font(.subheadline.weight(.medium)).padding(.bottom, 6)
            ForEach(records) { session in
                SessionRow(session: session)
                if session.id != records.last?.id { Divider() }
            }
        }
        .card()
    }
}
