import SwiftData
import SwiftUI

/// 現在のモードの完了履歴だけを新しい順に表示する。進行中は含めない。
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.footnote).foregroundStyle(.secondary)
                        HStack {
                            Text(session.purpose?.label ?? "回答なし")
                            Spacer()
                            Text(session.outcome?.label ?? "中断")
                        }
                        if session.temporaryUnlockStartedAt != nil {
                            let note = [session.reflection.flatMap { $0 == .skipped ? nil : "感想：\($0.label)" }]
                                .compactMap { $0 }.first
                            Text(["一時解除を開始", note].compactMap { $0 }.joined(separator: "・"))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}
