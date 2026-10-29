import FamilyControls
import ManagedSettings
import SwiftData
import SwiftUI

/// 1件の記録。何が起きたか、目的、解除していた時間、解除したもの（アイコンだけ）、感想を、必要な分だけ出す。
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
            if !unlockedItems.isEmpty {
                HStack(spacing: 8) {
                    ForEach(unlockedItems) { item in
                        ItemLabel(item: item).labelStyle(.iconOnly)
                    }
                }
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

    /// 解除したもの（アプリ・カテゴリ・ウェブサイト）。以前の版の保存形式（アプリのみ）も読める。
    var unlockedItems: [RestrictedItem] {
        RestrictedItems.decode(session.temporaryUnlockedApps).sortedItems
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

    /// 解除したものごとの回数と、解除していた時間の合計。
    private var itemTotals: [(item: RestrictedItem, count: Int, seconds: TimeInterval)] {
        var totals: [RestrictedItem: (Int, TimeInterval)] = [:]
        for session in today {
            for item in SessionRow(session: session).unlockedItems {
                let old = totals[item] ?? (0, 0)
                totals[item] = (old.0 + 1, old.1 + (session.unlockDuration ?? 0))
            }
        }
        return totals.map { (item: $0.key, count: $0.value.0, seconds: $0.value.1) }
            .sorted { $0.item.hashValue < $1.item.hashValue }
    }

    var body: some View {
        Group {
            if today.isEmpty {
                ContentUnavailableView("今日はまだありません。", systemImage: "tray")
            } else {
                List {
                    if kind == .wantsToUse, !itemTotals.isEmpty {
                        Section("解除したもの") {
                            ForEach(itemTotals, id: \.item) { item in
                                HStack {
                                    ItemLabel(item: item.item).labelStyle(.iconOnly)
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
    }

    private func totalText(_ count: Int, _ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return seconds < 60 ? "\(count)回・1分未満" : "\(count)回・約\(minutes)分"
    }
}
