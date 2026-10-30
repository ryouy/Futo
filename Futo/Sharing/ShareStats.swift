import Foundation

/// 共有する統計の選択。初期は、すべてオフ（詳細を初期オンにして、公開を急がせない）。
struct ShareSelection: Equatable {
    var showName = true            // 表示名は初期オン。匿名表示も選べる
    var counts = false             // 解除申込数・見送り数・中断数
    var purposes = false           // 利用目的の内訳
    var feelings = false           // 利用後の満足感（回答件数を併記）
    var phrase: SharePhrase?       // 定型のひとこと（任意）

    /// 統計の項目が1つも選ばれていなければ、公開しない。
    var hasStats: Bool { counts || purposes || feelings }
}

enum SharePeriod: String, CaseIterable, Identifiable {
    case thisWeek
    case lastWeek

    var id: String { rawValue }
    var label: String { self == .thisWeek ? tr("今週") : tr("先週") }
}

/// サーバーが受け付ける、定型のひとこと（IDだけを送る）。
enum SharePhrase: String, CaseIterable, Identifiable {
    case p1, p2, p3

    var id: String { rawValue }
    var text: String {
        switch self {
        case .p1: return tr("こんな感じでした。")
        case .p2: return tr("ひと呼吸の記録を、少しだけ共有します。")
        case .p3: return tr("ふと、立ち止まった記録です。")
        }
    }
}

/// サーバーへ送る、Web共有・フレンド共有の統計（選んだ項目だけ。選ばなかった項目は、キー自体を送らない）。
struct SharePayload: Codable, Equatable {
    struct Counts: Codable, Equatable { var wantsToUse: Int; var deferred: Int; var interrupted: Int }
    struct Purposes: Codable, Equatable { var contact: Int; var research: Int; var `break`: Int; var noReason: Int; var unanswered: Int }
    struct Feelings: Codable, Equatable { var satisfied: Int; var neutral: Int; var wishedLess: Int }

    var period: String
    var periodStart: String
    var periodEnd: String
    var timezone: String
    var isPartial: Bool
    var showName: Bool
    var counts: Counts?
    var purposes: Purposes?
    var feelings: Feelings?
    var phraseId: String?
    var expiresInDays: Int?
    var recipientUids: [String]?
    var idempotencyKey: String
}

enum ShareStatsBuilder {
    enum BuildError: Error, Equatable {
        case nothingSelected
    }

    private static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    private static func tally(_ records: [Session], where predicate: (Session) -> Bool) -> Int {
        records.reduce(0) { predicate($1) ? $0 + 1 : $0 }
    }

    /// 個人向けの統計と同じ定義（午前4時区切りの暦の週）で、指定の期間の記録から、選んだ項目だけを集計する。
    /// 端末の全履歴は送らない。対象は、現在のモード（実機）の、終わったひと呼吸だけ。
    static func make(
        sessions: [Session], mode: AppMode, period: SharePeriod, selection: ShareSelection,
        calendar: LogicalCalendar = LogicalCalendar(), now: Date = Date(),
        expiresInDays: Int? = 7, recipientUids: [String]? = nil, idempotencyKey: String = UUID().uuidString.lowercased()
    ) throws -> SharePayload {
        guard selection.hasStats else { throw BuildError.nothingSelected }
        let interval = period == .thisWeek ? calendar.weekInterval(containing: now) : calendar.previousWeekInterval(before: now)
        let records = PeriodInsights.records(sessions: sessions, mode: mode, interval: interval).filter { !$0.phase.isOpen }

        var payload = SharePayload(
            period: period.rawValue,
            periodStart: iso(interval.start),
            periodEnd: iso(interval.end),
            timezone: calendar.calendar.timeZone.identifier,
            isPartial: period == .thisWeek && now < interval.end,
            showName: selection.showName,
            counts: nil, purposes: nil, feelings: nil,
            phraseId: selection.phrase?.rawValue,
            expiresInDays: expiresInDays,
            recipientUids: recipientUids,
            idempotencyKey: idempotencyKey
        )
        if selection.counts {
            let wants: Int = tally(records) { $0.outcome == .wantsToUse }
            let deferred: Int = tally(records) { $0.outcome == .deferred }
            // 終わっていて、結果が付かなかったものも、中断に数える（個人向けの統計と同じ）
            let interrupted: Int = tally(records) { $0.outcome == .interrupted || $0.outcome == nil }
            payload.counts = SharePayload.Counts(wantsToUse: wants, deferred: deferred, interrupted: interrupted)
        }
        if selection.purposes {
            let contact: Int = tally(records) { $0.purpose == .contact }
            let research: Int = tally(records) { $0.purpose == .research }
            let change: Int = tally(records) { $0.purpose == .change }
            let noReason: Int = tally(records) { $0.purpose == .noReason }
            let unanswered: Int = tally(records) { $0.purpose == nil }
            payload.purposes = SharePayload.Purposes(contact: contact, research: research, break: change, noReason: noReason, unanswered: unanswered)
        }
        if selection.feelings {
            // 「答えない」は回答に数えない。未回答の補完や、実利用の推測はしない
            let satisfied: Int = tally(records) { $0.reflection == .satisfied }
            let neutral: Int = tally(records) { $0.reflection == .neutral }
            let wishedLess: Int = tally(records) { $0.reflection == .wishedLess }
            payload.feelings = SharePayload.Feelings(satisfied: satisfied, neutral: neutral, wishedLess: wishedLess)
        }
        return payload
    }
}

enum DisplayName {
    /// Googleから受け取った名前を、1〜20文字・制御文字なしに整える。取れなければ「ふと」
    static func initial(from raw: String?) -> String {
        let cleaned = (raw ?? "").precomposedStringWithCanonicalMapping
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\u{2028}" && $0 != "\u{2029}" }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(20)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? tr("ふと") : limited
    }
}
