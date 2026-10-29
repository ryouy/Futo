import Foundation

/// 履歴・今日の詳細に出す、1件ぶんの分かりやすい言い方。
extension Session {
    /// 結果の見出し。「使いたい」「中断」のような曖昧な言葉を避け、何が起きたかで言う。
    var resultTitle: String {
        switch outcome {
        case .deferred: return "やめた"
        case .wantsToUse: return temporaryUnlockStartedAt != nil ? "解除した" : "使いたいと答えた"
        case .interrupted, nil: return "途中でやめた"
        }
    }

    /// 制限を解除していた時間。解除中、または解除していなければ nil。
    /// 「使った時間」ではなく、「解除していた時間」。
    var unlockDuration: TimeInterval? {
        guard let started = temporaryUnlockStartedAt, let ended = temporaryUnlockEndedAt else { return nil }
        return max(0, ended.timeIntervalSince(started))
    }

    var isUnlockInProgress: Bool {
        temporaryUnlockStartedAt != nil && temporaryUnlockEndedAt == nil
    }

    /// 「解除 約3分」「解除 1分未満」「解除中」。解除していなければ nil。
    var unlockDurationText: String? {
        guard temporaryUnlockStartedAt != nil else { return nil }
        guard let duration = unlockDuration else { return "解除中" }
        if duration < 60 { return "解除 1分未満" }
        return "解除 約\(Int((duration / 60).rounded()))分"
    }

    var purposeText: String {
        guard let purpose else { return "目的：答えなかった" }
        return "目的：\(purpose.label)"
    }
}

/// 直近の日ごとの集計（グラフ用）。論理日（午前4時区切り）で数える。
struct DayStat: Identifiable, Equatable {
    var dayKey: String
    var label: String
    var deferred = 0
    var wantsToUse = 0
    var interrupted = 0
    /// 解除していた時間の合計（秒）。解除中のものは含めない
    var unlockSeconds: Double = 0

    var id: String { dayKey }
    var total: Int { deferred + wantsToUse + interrupted }
}

enum DailySeries {
    /// 今日を含む直近 `days` 日。記録が無い日も0件として並べる。
    static func make(sessions: [Session], mode: AppMode, calendar: LogicalCalendar, now: Date, days: Int = 7) -> [DayStat] {
        var stats: [DayStat] = []
        var cursor = calendar.dayInterval(containing: now)
        for _ in 0..<days {
            let day = cursor
            let comps = calendar.calendar.dateComponents([.month, .day], from: day.start)
            var stat = DayStat(dayKey: calendar.dayKey(for: day.start), label: "\(comps.month ?? 0)/\(comps.day ?? 0)")
            for s in sessions where s.mode == mode && s.phase != .choosingPurpose && day.contains(s.startedAt) {
                switch s.outcome {
                case .deferred: stat.deferred += 1
                case .wantsToUse: stat.wantsToUse += 1
                case .interrupted, nil: stat.interrupted += 1
                }
                if let duration = s.unlockDuration { stat.unlockSeconds += duration }
            }
            stats.append(stat)
            cursor = calendar.dayInterval(containing: day.start.addingTimeInterval(-1))
        }
        return stats.reversed()
    }
}
