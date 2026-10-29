import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

/// 1件の記録。何が起きたか（やめた／解除した／途中でやめた）、目的、解除していた時間、解除したアプリ、感想を、必要な分だけ出す。
struct SessionRow: View {
    let session: Session
    var showsDate = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(session.resultTitle).font(.headline.weight(.medium))
                Spacer()
                Text(timeText).font(.footnote).foregroundStyle(.secondary)
            }
            Text([session.purposeText, session.unlockDurationText].compactMap { $0 }.joined(separator: "　・　"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(unlockedTokens, id: \.self) { token in
                Label(token).font(.footnote)
            }
            if let reflection = session.reflection, reflection != .skipped {
                Text("感想：\(reflection.label)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        showsDate
            ? session.startedAt.formatted(.dateTime.month().day().hour().minute())
            : session.startedAt.formatted(.dateTime.hour().minute())
    }

    var unlockedTokens: [ApplicationToken] {
        guard let data = session.temporaryUnlockedApps,
              let tokens = try? JSONDecoder().decode(Set<ApplicationToken>.self, from: data) else { return [] }
        return tokens.sorted { $0.hashValue < $1.hashValue }
    }
}

/// 現在のモードの完了した記録を、新しい順に表示する。
struct HistoryView: View {
    let mode: AppMode
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    private var finished: [Session] {
        sessions.filter { $0.mode == mode && !$0.phase.isOpen }
    }

    var body: some View {
        Group {
            if finished.isEmpty {
                ContentUnavailableView("まだ記録はありません。", systemImage: "tray")
            } else {
                List(finished) { session in
                    SessionRow(session: session)
                        .listRowBackground(Theme.card)
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}

/// 「今日やめた」「今日使いたかった」を押したときの中身。今日の該当する記録と、解除したアプリ。
struct TodayDetailView: View {
    let mode: AppMode
    let kind: SessionOutcome
    @Query(sort: \Session.startedAt, order: .reverse) private var sessions: [Session]

    private var today: [Session] {
        let day = LogicalCalendar().dayInterval(containing: Date())
        return sessions.filter { $0.mode == mode && $0.outcome == kind && day.contains($0.completedAt ?? $0.startedAt) }
    }

    /// 解除したアプリごとの回数と、解除していた時間の合計。
    private var appTotals: [(token: ApplicationToken, count: Int, seconds: TimeInterval)] {
        var totals: [ApplicationToken: (Int, TimeInterval)] = [:]
        for session in today {
            let row = SessionRow(session: session)
            for token in row.unlockedTokens {
                let old = totals[token] ?? (0, 0)
                totals[token] = (old.0 + 1, old.1 + (session.unlockDuration ?? 0))
            }
        }
        return totals.map { (token: $0.key, count: $0.value.0, seconds: $0.value.1) }
            .sorted { $0.token.hashValue < $1.token.hashValue }
    }

    var body: some View {
        Group {
            if today.isEmpty {
                ContentUnavailableView("今日はまだありません。", systemImage: "tray")
            } else {
                List {
                    if kind == .wantsToUse, !appTotals.isEmpty {
                        Section("解除したアプリ") {
                            ForEach(appTotals, id: \.token) { item in
                                HStack {
                                    Label(item.token)
                                    Spacer()
                                    Text(totalText(item.count, item.seconds))
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                .frame(minHeight: 44)
                                .listRowBackground(Theme.card)
                            }
                        }
                    }
                    Section("今日の記録") {
                        ForEach(today) { session in
                            SessionRow(session: session, showsDate: false)
                                .listRowBackground(Theme.card)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(kind == .deferred ? "今日やめた" : "今日使いたかった")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { GraphView(mode: mode) } label: { Label("グラフ", systemImage: "chart.bar") }
            }
        }
    }

    private func totalText(_ count: Int, _ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return seconds < 60 ? "\(count)回・1分未満" : "\(count)回・約\(minutes)分"
    }
}
