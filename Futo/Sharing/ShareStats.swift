import Foundation

/// 共有する統計の選択。初期は、すべてオフ（詳細を初期オンにして、公開を急がせない）。
struct ShareSelection: Equatable, Codable {
    var showName = true            // 表示名は初期オン。匿名表示も選べる
    var counts = false             // 解除申込数・見送り数・中断数
    var purposes = false           // 利用目的の内訳
    var feelings = false           // 利用後の満足感（回答件数を併記）
    var restriction = false        // 制限の管理（一時停止・終了の回数）。初期はオフ
    var apps = true                // よく解除したアプリ名と回数（初期はオン。名前を読み取れないときは、含まれない）
    var phrase: SharePhrase?       // 定型のひとこと（任意。Webリンク用）
    var message = ""              // フレンドへの一言（自由入力。フレンド共有だけ）

    /// 統計の項目が1つも選ばれていなければ、公開しない。
    var hasStats: Bool { counts || purposes || feelings || apps || restriction }
}

enum SharePeriod: String, CaseIterable, Identifiable {
    case thisWeek
    case lastWeek
    /// 記録のある、全期間（最初の記録から、いままで）
    case all

    var id: String { rawValue }
    var label: String {
        switch self {
        case .thisWeek: return tr("今週")
        case .lastWeek: return tr("先週")
        case .all: return tr("全期間")
        }
    }
}

/// 継続共有の更新で送る内容（受信者・冪等キー・期限は含めない。サーバーの更新APIの形）。
struct ShareUpdatePayload: Codable, Equatable {
    var period: String
    var periodStart: String
    var periodEnd: String
    var timezone: String
    var isPartial: Bool
    var showName: Bool
    var counts: SharePayload.Counts?
    var purposes: SharePayload.Purposes?
    var feelings: SharePayload.Feelings?
    var apps: [AppCount]?
    var restriction: RestrictionCounts?
    var phraseId: String?
    var message: String?
}

/// サーバーが受け付ける、定型のひとこと（IDだけを送る）。
enum SharePhrase: String, CaseIterable, Identifiable, Codable {
    case p1, p2, p3

    var id: String { rawValue }
    var text: String {
        switch self {
        case .p1: return tr("こんな感じでした")
        case .p2: return tr("ひと呼吸の記録を、少しだけ共有します")
        case .p3: return tr("ふと、立ち止まった記録です")
        }
    }
}

/// サーバーへ送る、Web共有・フレンド共有の統計（選んだ項目だけ。選ばなかった項目は、キー自体を送らない）。
/// 制限の一時停止・終了の回数。
struct RestrictionCounts: Codable, Equatable {
    var pauses: Int
    var ends: Int
}

/// アプリ名と、一時解除した回数。
struct AppCount: Codable, Equatable {
    var name: String
    var count: Int
}

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
    var apps: [AppCount]?
    var restriction: RestrictionCounts?
    var phraseId: String?
    /// フレンドへの一言（自由入力）。Webの公開リンクには付けない
    var message: String?
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
        expiresInDays: Int? = 7, recipientUids: [String]? = nil, idempotencyKey: String = UUID().uuidString.lowercased(),
        allowsMessage: Bool = false,
        appCounts: (DateInterval) -> [AppCount] = { _ in [] },
        restrictionCounts: (DateInterval) -> RestrictionCounts = { _ in RestrictionCounts(pauses: 0, ends: 0) }
    ) throws -> SharePayload {
        guard selection.hasStats else { throw BuildError.nothingSelected }
        let interval: DateInterval
        switch period {
        case .thisWeek: interval = calendar.weekInterval(containing: now)
        case .lastWeek: interval = calendar.previousWeekInterval(before: now)
        case .all:
            // 最初の記録から、いままで。サーバーが受け付ける最長（10年）を超えないようにする
            let closed = PeriodInsights.records(sessions: sessions, mode: mode, interval: nil).filter { !$0.phase.isOpen }
            let earliest = closed.map(\.startedAt).min() ?? now.addingTimeInterval(-86_400)
            let limit = now.addingTimeInterval(-3_600 * 86_400)
            interval = DateInterval(start: min(max(earliest, limit), now.addingTimeInterval(-1)), end: now)
        }
        let records = PeriodInsights.records(sessions: sessions, mode: mode, interval: period == .all ? nil : interval).filter { !$0.phase.isOpen }
            .filter { period != .all || $0.startedAt >= interval.start }

        var payload = SharePayload(
            period: period.rawValue,
            periodStart: iso(interval.start),
            periodEnd: iso(interval.end),
            timezone: calendar.calendar.timeZone.identifier,
            isPartial: period == .thisWeek && now < interval.end,
            showName: selection.showName,
            counts: nil, purposes: nil, feelings: nil, apps: nil, restriction: nil,
            phraseId: allowsMessage ? nil : selection.phrase?.rawValue,
            message: allowsMessage ? ShareMessage.normalized(selection.message) : nil,
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
        if selection.apps {
            // 名前を読み取れたものだけ。1件もなければ、項目ごと付けない（読み取れない名前を、推測しない）
            let apps = AppUsageSummary.sanitized(appCounts(interval))
            if !apps.isEmpty { payload.apps = apps }
        }
        if selection.restriction { payload.restriction = restrictionCounts(interval) }
        // 項目を選んでいても、中身が何もなければ、共有しない
        guard payload.counts != nil || payload.purposes != nil || payload.feelings != nil || payload.apps != nil || payload.restriction != nil else { throw BuildError.nothingSelected }
        return payload
    }
}

extension SharePayload {
    /// 継続共有の更新用（受信者・冪等キー・期限を除く）
    var updateBody: ShareUpdatePayload {
        ShareUpdatePayload(period: period, periodStart: periodStart, periodEnd: periodEnd, timezone: timezone, isPartial: isPartial,
                           showName: showName, counts: counts, purposes: purposes, feelings: feelings, apps: apps, restriction: restriction, phraseId: phraseId, message: message)
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

/// フレンドへの一言（自由入力）。サーバーと同じ規則：1〜60文字、制御文字・URLは不可。
enum ShareMessage {
    static let maxLength = 60

    /// 整えた文字列（空なら nil）。長すぎるものは、先頭の60文字に切る。
    static func normalized(_ raw: String) -> String? {
        let cleaned = raw.precomposedStringWithCanonicalMapping
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\u{2028}" && $0 != "\u{2029}" }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? nil : limited
    }

    /// URLのように見える文字列は、送れない（迷惑な誘導を防ぐ）。
    static func looksLikeLink(_ text: String) -> Bool {
        let lower = text.lowercased()
        if lower.contains("://") || lower.contains("www.") { return true }
        return lower.range(of: #"\b[a-z0-9-]+\.(com|net|org|jp|io|co|app|me|ly|xyz)\b"#, options: .regularExpression) != nil
    }
}

/// よく解除したアプリ（名前と回数）。名前は、解除した対象から読み取れたものだけ。
enum AppUsageSummary {
    static let maxItems = 10
    static let maxNameLength = 40

    /// 一時解除を始めたひと呼吸を、対象ごとに数える（1回の解除で複数の対象なら、それぞれに1回）。
    /// 名前が読み取れない対象は、含めない。回数の多い順に、最大10件。
    static func top<Key: Hashable>(
        sessions: [Session], mode: AppMode, interval: DateInterval?,
        keys: (Session) -> [Key], name: (Key) -> String?
    ) -> [AppCount] {
        var counts: [Key: Int] = [:]
        var order: [Key] = []
        for session in sessions {
            guard session.mode == mode, session.phase == .completed, session.outcome == .wantsToUse,
                  let unlockedAt = session.temporaryUnlockStartedAt else { continue }
            if let interval, !interval.contains(unlockedAt) { continue }
            for key in Set(keys(session)) {
                if counts[key] == nil { order.append(key) }
                counts[key, default: 0] += 1
            }
        }
        // 同じ名前（同名の別アプリ・カテゴリなど）は、1行にまとめる
        var byName: [String: Int] = [:]
        var names: [String] = []
        for key in order {
            guard let raw = name(key), let clean = cleanName(raw) else { continue }
            if byName[clean] == nil { names.append(clean) }
            byName[clean, default: 0] += counts[key] ?? 0
        }
        return names.map { AppCount(name: $0, count: byName[$0] ?? 0) }
            .sorted { $0.count > $1.count }
            .prefix(maxItems).map { $0 }
    }

    /// 表示用に整える（制御文字を除き、40文字まで。空なら nil）。
    static func cleanName(_ raw: String) -> String? {
        let cleaned = raw.precomposedStringWithCanonicalMapping
            .unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) && $0 != "\u{2028}" && $0 != "\u{2029}" }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(cleaned.prefix(maxNameLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? nil : limited
    }

    static func sanitized(_ apps: [AppCount]) -> [AppCount] {
        apps.compactMap { app in cleanName(app.name).map { AppCount(name: $0, count: max(0, app.count)) } }
            .filter { $0.count > 0 }
            .prefix(maxItems).map { $0 }
    }
}
