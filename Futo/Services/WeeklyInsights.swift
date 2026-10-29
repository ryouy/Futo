import Foundation

enum TimeBand: String, CaseIterable, Identifiable {
    case morning, daytime, evening, night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .morning: return "朝（5〜11時）"
        case .daytime: return "昼（11〜17時）"
        case .evening: return "夕方（17〜22時）"
        case .night: return "夜（22〜5時）"
        }
    }

    static func band(forHour hour: Int) -> TimeBand {
        switch hour {
        case 5..<11: return .morning
        case 11..<17: return .daytime
        case 17..<22: return .evening
        default: return .night
        }
    }
}

/// 「今週」の傾向。記録された操作だけを数える。
/// 実際の使用時間・節約時間・対象アプリを開こうとした回数は、取得していないので出さない。
struct WeeklyInsights: Equatable {
    var total = 0
    var deferred = 0
    var wantsToUse = 0
    var interrupted = 0
    /// 一時解除を始めた件数。実際に使ったかどうかは分からない。
    var unlockStarted = 0
    var purposeCounts: [Purpose: Int] = [:]
    var purposeSkipped = 0
    var reflectionCounts: [Reflection: Int] = [:]
    var bandCounts: [TimeBand: Int] = [:]
    /// 前週にも今週にも記録があるときだけ入る
    var previousTotal: Int?

    var answeredPurposes: Int { purposeCounts.values.reduce(0, +) }
    /// 「答えない」を除いた感想の回答数
    var answeredReflections: Int { reflectionCounts.values.reduce(0, +) }
    var topBand: TimeBand? {
        guard let best = bandCounts.max(by: { $0.value < $1.value }), best.value > 0 else { return nil }
        return best.key
    }

    static func make(sessions: [Session], mode: AppMode, calendar: LogicalCalendar, now: Date) -> WeeklyInsights {
        func records(in interval: DateInterval) -> [Session] {
            sessions.filter { $0.mode == mode && interval.contains($0.startedAt) && $0.phase != .choosingPurpose }
        }
        let week = records(in: calendar.weekInterval(containing: now))
        var result = WeeklyInsights()
        result.total = week.count
        for session in week {
            switch session.outcome {
            case .deferred: result.deferred += 1
            case .wantsToUse: result.wantsToUse += 1
            case .interrupted: result.interrupted += 1
            case nil: break
            }
            if session.temporaryUnlockStartedAt != nil { result.unlockStarted += 1 }
            if let purpose = session.purpose {
                result.purposeCounts[purpose, default: 0] += 1
            } else {
                result.purposeSkipped += 1
            }
            if let reflection = session.reflection, reflection != .skipped {
                result.reflectionCounts[reflection, default: 0] += 1
            }
            let hour = calendar.calendar.component(.hour, from: session.startedAt)
            result.bandCounts[TimeBand.band(forHour: hour), default: 0] += 1
        }
        let previous = records(in: calendar.previousWeekInterval(before: now)).count
        if previous > 0, result.total > 0 { result.previousTotal = previous }
        return result
    }
}
