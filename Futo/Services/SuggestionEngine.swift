import Foundation

enum SuggestionKind: String, Codable {
    case waitLonger
    case waitShorter
    case nightEarlier
}

/// 提案を受け入れたときに変える設定。既存の設定だけを対象にする。
enum SuggestionChange: Codable, Equatable {
    case waitSeconds(Double)
    case nightMinute(Int)
}

enum SuggestionStatus: String, Codable {
    case pending
    case changed
    case kept
    case skipped
}

struct Suggestion: Codable, Equatable {
    var weekKey: String
    var kind: SuggestionKind
    var title: String
    /// 根拠となる件数だけを述べる。原因や気持ちは述べない。
    var evidence: String
    var currentText: String
    var proposedText: String
    var change: SuggestionChange
    var status: SuggestionStatus = .pending
}

struct SuggestionState: Codable, Equatable {
    var current: Suggestion?
    /// 「今のまま」を選んだ提案を、しばらく出さないための期限
    var suppressedUntil: [String: Date] = [:]
}

/// 週1回まで、記録に基づく小さな工夫を1つだけ提案する。設定は自動では変えない。
enum SuggestionEngine {
    /// 傾向として述べるのに必要な、関連する記録の件数
    static let minimumRecords = 5
    static let keepSuppressionDays = 28

    /// 今表示すべき提案（未回答のもの）。今週すでに回答済みなら nil。
    static func evaluate(state: inout SuggestionState, sessions: [Session], mode: AppMode,
                         preferences: Preferences, calendar: LogicalCalendar, now: Date) -> Suggestion? {
        let weekKey = calendar.dayKey(for: calendar.weekInterval(containing: now).start)
        if let current = state.current, current.weekKey == weekKey {
            return current.status == .pending ? current : nil
        }
        guard let candidate = candidate(state: state, sessions: sessions, mode: mode,
                                        preferences: preferences, calendar: calendar, now: now, weekKey: weekKey) else {
            return nil
        }
        state.current = candidate
        return candidate
    }

    static func resolve(state: inout SuggestionState, status: SuggestionStatus, now: Date,
                        calendar: Calendar = .current) {
        guard var current = state.current, current.status == .pending else { return }
        current.status = status
        state.current = current
        if status == .kept,
           let until = calendar.date(byAdding: .day, value: keepSuppressionDays, to: now) {
            state.suppressedUntil[current.kind.rawValue] = until
        }
    }

    // MARK: 候補

    private static func candidate(state: SuggestionState, sessions: [Session], mode: AppMode,
                                  preferences: Preferences, calendar: LogicalCalendar, now: Date,
                                  weekKey: String) -> Suggestion? {
        let since = now.addingTimeInterval(-7 * 86_400)
        let records = sessions.filter {
            $0.mode == mode && $0.startedAt >= since && $0.startedAt <= now && $0.phase != .choosingPurpose
        }
        func allowed(_ kind: SuggestionKind) -> Bool {
            if let until = state.suppressedUntil[kind.rawValue], until > now { return false }
            return true
        }

        let chosen = records.filter { $0.outcome == .deferred || $0.outcome == .wantsToUse }
        let wants = chosen.filter { $0.outcome == .wantsToUse }.count
        let currentWait = preferences.effectiveWaitSeconds
        let options = Preferences.waitOptions

        if allowed(.waitLonger), chosen.count >= minimumRecords, wants * 10 >= chosen.count * 6,
           let longer = options.first(where: { $0 > currentWait }) {
            return Suggestion(
                weekKey: weekKey, kind: .waitLonger,
                title: "待機時間を長くしてみますか？",
                evidence: "7日間で、待機のあと「使いたい」は\(chosen.count)件中\(wants)件。",
                currentText: "待機時間 \(durationText(seconds: currentWait))",
                proposedText: "待機時間 \(durationText(seconds: longer))",
                change: .waitSeconds(longer))
        }

        if preferences.nightEnabled, allowed(.nightEarlier) {
            let nightStart = calendar.logicalMinute(clockMinute: preferences.nightMinute)
            let late = records.filter { calendar.logicalMinute(of: $0.startedAt) >= nightStart }.count
            let earlier = max(17 * 60, preferences.nightMinute - 60)
            if late >= minimumRecords, earlier < preferences.nightMinute {
                return Suggestion(
                    weekKey: weekKey, kind: .nightEarlier,
                    title: "夜の振り返りを早めますか？",
                    evidence: "\(clockText(minute: preferences.nightMinute))より後の記録が、7日間で\(late)件。",
                    currentText: "夜の振り返り \(clockText(minute: preferences.nightMinute))",
                    proposedText: "夜の振り返り \(clockText(minute: earlier))",
                    change: .nightMinute(earlier))
            }
        }

        let interrupted = records.filter { $0.outcome == .interrupted }.count
        if allowed(.waitShorter), interrupted >= minimumRecords,
           let shorter = options.last(where: { $0 < currentWait }) {
            return Suggestion(
                weekKey: weekKey, kind: .waitShorter,
                title: "待機時間を短くしてみますか？",
                evidence: "7日間で、途中でやめたのは\(interrupted)件。",
                currentText: "待機時間 \(durationText(seconds: currentWait))",
                proposedText: "待機時間 \(durationText(seconds: shorter))",
                change: .waitSeconds(shorter))
        }
        return nil
    }
}
