import Foundation

/// 記録の「日ごと・アプリごと」の集計。表示を簡素にするだけで、元の記録（時刻など）は変えない。
///
/// 数えるのは「一時解除を実際に始めた回数」だけ。実際の使用回数は取得できないので、「使用」とは呼ばない。
/// 見送り・中断・制限全体の一時停止・開発用の解除は、そもそも含まない（一時解除を始めたひと呼吸だけが対象）。
enum DailyUnlockSummary {
    struct Row<Key: Hashable>: Identifiable {
        /// 解除した対象。nil は、対象を記録していない解除（以前の版の記録）
        var key: Key?
        var count: Int
        /// この行に含まれるひと呼吸（詳細で、時刻などを見せる）。新しい順
        var sessions: [Session]

        var id: String { key.map { "\($0)" } ?? "unknown" }
    }

    struct Day<Key: Hashable>: Identifiable {
        var day: Date
        /// この日に一時解除を始めた回数（対象が複数でも、1回は1回）
        var unlockCount: Int
        var rows: [Row<Key>]

        var id: Date { day }
    }

    /// - Parameters:
    ///   - mode: デモと実機は混ぜない
    ///   - interval: 期間（一時解除を始めた時刻で判定）。nil は全期間
    ///   - calendar: 日付の区切り（現地時刻）
    ///   - keys: 1回の解除で、解除した対象
    static func make<Key: Hashable>(
        sessions: [Session], mode: AppMode, interval: DateInterval?, calendar: Calendar = .current,
        keys: (Session) -> [Key]
    ) -> [Day<Key>] {
        var byDay: [Date: [Session]] = [:]
        for session in sessions {
            guard session.mode == mode, session.phase == .completed, session.outcome == .wantsToUse,
                  let unlockedAt = session.temporaryUnlockStartedAt else { continue }
            if let interval, !interval.contains(unlockedAt) { continue }
            byDay[calendar.startOfDay(for: unlockedAt), default: []].append(session)
        }

        return byDay.keys.sorted(by: >).map { day in
            let daySessions = (byDay[day] ?? []).sorted { ($0.temporaryUnlockStartedAt ?? .distantPast) > ($1.temporaryUnlockStartedAt ?? .distantPast) }
            var order: [Key?] = []
            var grouped: [Key?: [Session]] = [:]
            for session in daySessions {
                let sessionKeys = keys(session)
                let targets: [Key?] = sessionKeys.isEmpty ? [nil] : sessionKeys.map { Optional($0) }
                for key in targets {
                    if grouped[key] == nil { order.append(key) }
                    grouped[key, default: []].append(session)
                }
            }
            let rows = order.map { key in Row(key: key, count: grouped[key]?.count ?? 0, sessions: grouped[key] ?? []) }
                .sorted { $0.count > $1.count }
            return Day(day: day, unlockCount: daySessions.count, rows: rows)
        }
    }
}
