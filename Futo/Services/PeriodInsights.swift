import Foundation

enum TimeBand: String, CaseIterable, Identifiable {
    case morning, daytime, evening, night

    var id: String { rawValue }

    /// 何時かは見せず、時間帯の名前だけ。
    var label: String {
        switch self {
        case .morning: return "朝"
        case .daytime: return "昼"
        case .evening: return "夕方"
        case .night: return "夜"
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

/// 記録を見る期間。
enum InsightPeriod: String, CaseIterable, Identifiable {
    case week, month, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .week: return "今週"
        case .month: return "今月"
        case .all: return "すべて"
        }
    }

    /// nil は全期間。
    func interval(calendar: LogicalCalendar, now: Date) -> DateInterval? {
        switch self {
        case .week: return calendar.weekInterval(containing: now)
        case .month: return calendar.monthInterval(containing: now)
        case .all: return nil
        }
    }
}

/// 期間ごとの集計。記録された操作だけを数える。
/// 実際の使用時間・節約時間・対象を開こうとした回数は、取得していないので出さない。
struct PeriodInsights: Equatable {
    var total = 0
    var deferred = 0
    var wantsToUse = 0
    var interrupted = 0
    /// 一時解除を始めた件数。実際に使ったかどうかは分からない。
    var unlockStarted = 0
    /// 解除していた時間の合計（終了が記録されたものだけ）
    var unlockSeconds: TimeInterval = 0
    var purposeCounts: [Purpose: Int] = [:]
    var purposeSkipped = 0
    var reflectionCounts: [Reflection: Int] = [:]
    var bandCounts: [TimeBand: Int] = [:]

    var answeredReflections: Int { reflectionCounts.values.reduce(0, +) }

    /// 期間内の記録（開始したひと呼吸）。
    static func records(sessions: [Session], mode: AppMode, interval: DateInterval?) -> [Session] {
        sessions.filter { session in
            guard session.mode == mode, session.phase != .choosingPurpose else { return false }
            return interval?.contains(session.startedAt) ?? true
        }
    }

    static func make(sessions: [Session], mode: AppMode, period: InsightPeriod,
                     calendar: LogicalCalendar, now: Date) -> PeriodInsights {
        let range = period.interval(calendar: calendar, now: now)
        var result = PeriodInsights()
        for session in records(sessions: sessions, mode: mode, interval: range) {
            result.total += 1
            switch session.outcome {
            case .deferred: result.deferred += 1
            case .wantsToUse: result.wantsToUse += 1
            case .interrupted, nil: result.interrupted += 1
            }
            if session.temporaryUnlockStartedAt != nil { result.unlockStarted += 1 }
            if let duration = session.unlockDuration { result.unlockSeconds += duration }
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
        return result
    }
}
