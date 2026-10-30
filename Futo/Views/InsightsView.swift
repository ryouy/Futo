import SwiftData
import SwiftUI

/// 記録の画面。「今週／今月／すべて」を切り替えて、集計・円グラフ・記録の一覧を1画面で見る。
struct RecordsView: View {
    let mode: AppMode
    @State private var period: InsightPeriod = .week
    @State private var detail: DayDetail?
    /// 開いている日（日付をタップすると、その日のアプリごとの回数が見える）
    @State private var expandedDays: Set<Date> = []
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]
    @Query(sort: \RestrictionEvent.at, order: .reverse) private var events: [RestrictionEvent]

    var body: some View {
        let calendar = LogicalCalendar()
        let now = Date()
        let insights = PeriodInsights.make(sessions: sessions, mode: mode, period: period, calendar: calendar, now: now)
        let interval = period.interval(calendar: calendar, now: now)
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
                    if insights.total == 0 && RestrictionEventSummary.counts(events, mode: mode, interval: interval).isEmpty {
                        Text(tr("この期間の記録はまだありません。")).foregroundStyle(.secondary).card()
                    } else {
                        countsCard(insights, restriction: RestrictionEventSummary.counts(events, mode: mode, interval: interval))
                        PieCard(title: tr("目的"), slices: breakdown.purposes)
                        if insights.answeredReflections > 0 {
                            PieCard(title: tr("感想"), slices: breakdown.reflections)
                        }
                        bandCard(insights)
                        dailyCard(interval: interval)
                    }
                }
                .padding(20)
                .animation(.easeInOut(duration: 0.3), value: period)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(tr("記録"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { DayDetailView(detail: $0).presentationBackground(Theme.background) }
    }

    // MARK: カード

    private func countsCard(_ w: PeriodInsights, restriction r: RestrictionEventSummary.Counts) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            row(tr("ひと呼吸"), "\(w.total)")
            row(tr("やめておく"), "\(w.deferred)")
            row(tr("使いたい"), "\(w.wantsToUse)")
            if w.answeredReflections > 0 { row(tr("感想に答えた"), "\(w.answeredReflections)") }
            if r.pauses > 0 { row(tr("制限の一時停止"), tr("{0}回", "\(r.pauses)")) }
            if r.ends > 0 { row(tr("制限の終了"), tr("{0}回", "\(r.ends)")) }
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

    /// 日ごと・アプリごとの「一時解除」の回数。時刻などは、行を開いたときに見られる。
    private func dailyCard(interval: DateInterval?) -> some View {
        let days = DailyUnlockSummary.make(sessions: sessions, mode: mode, interval: interval) { session in
            RestrictedItems.decode(session.temporaryUnlockedApps).sortedItems
        }
        return VStack(alignment: .leading, spacing: 14) {
            Text(tr("一時解除（日ごと）")).font(.subheadline.weight(.medium))
            if days.isEmpty {
                Text(tr("この期間に、一時解除した記録はありません。")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(days) { day in
                let expanded = expandedDays.contains(day.day)
                VStack(alignment: .leading, spacing: 0) {
                    // 最初は、日付と一時解除の回数だけ。タップで、アプリごとの詳細が開く。
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if expanded { expandedDays.remove(day.day) } else { expandedDays.insert(day.day) }
                        }
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(day.day.formatted(Date.FormatStyle().month().day().weekday(.abbreviated).locale(LanguageStore.shared.language.locale)))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(tr("一時解除 {0}回", "\(day.unlockCount)")).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(expanded ? 90 : 0))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityValue(expanded ? tr("開いています") : tr("閉じています"))

                    if expanded {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(day.rows) { row in
                                Button { detail = DayDetail(day: day.day, key: row.key, sessions: row.sessions) } label: {
                                    HStack(spacing: 8) {
                                        Group {
                                            if let item = row.key { ItemLabel(item: item).lineLimit(1) } else { Text(tr("対象の記録なし")) }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(tr("{0}回", "\(row.count)")).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                        Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint(tr("時刻などの詳細を開きます"))
                            }
                        }
                        .padding(.leading, 12)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                if day.id != days.last?.id { Divider() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// 日ごとの行を開いたときの詳細。1回ごとの時刻・目的・解除していた時間・感想を見せる。
struct DayDetail: Identifiable {
    var day: Date
    var key: RestrictedItem?
    var sessions: [Session]
    var id: String { "\(day.timeIntervalSince1970)-\(key.map { "\($0)" } ?? "unknown")" }
}

struct DayDetailView: View {
    let detail: DayDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(detail.day.formatted(Date.FormatStyle().year().month().day().weekday(.wide).locale(LanguageStore.shared.language.locale)))
                        .font(.footnote).foregroundStyle(.secondary)
                    Group {
                        if let item = detail.key { ItemLabel(item: item) } else { Text(tr("対象の記録なし")) }
                    }
                    .font(.headline)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(detail.sessions) { session in
                            SessionRow(session: session, showsDate: false)
                            if session.id != detail.sessions.last?.id { Divider() }
                        }
                    }
                    .card()
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(tr("一時解除の詳細"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("閉じる")) { dismiss() } } }
        }
    }
}
