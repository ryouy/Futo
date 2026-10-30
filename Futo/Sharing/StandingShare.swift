import Foundation

/// 継続共有（フレンドに、許可した項目だけを、アプリを開いたときに更新して見せ続ける）の、端末内の設定。
/// 中身の統計は持たない（選んだ項目・期間・共有のIDだけ）。常時同期ではなく、アプリを開いたとき・手動のときだけ更新する。
struct StandingShareConfig: Codable, Equatable, Identifiable {
    var shareId: String
    var period: String
    var showName: Bool
    var counts: Bool
    var purposes: Bool
    var feelings: Bool
    /// アプリ名を含めるか（古い設定には無いので、既定は含める）
    var apps: Bool? = nil
    var restriction: Bool? = nil
    var phraseId: String?
    /// フレンドへの一言（本人が入力した文）。統計の値ではない
    var message: String? = nil
    var lastRefreshedAt: Date

    var id: String { shareId }

    init(shareId: String, period: SharePeriod, selection: ShareSelection, refreshedAt: Date) {
        self.shareId = shareId
        self.period = period.rawValue
        self.showName = selection.showName
        self.counts = selection.counts
        self.purposes = selection.purposes
        self.feelings = selection.feelings
        self.apps = selection.apps
        self.restriction = selection.restriction
        self.phraseId = selection.phrase?.rawValue
        self.message = ShareMessage.normalized(selection.message)
        self.lastRefreshedAt = refreshedAt
    }

    var sharePeriod: SharePeriod { SharePeriod(rawValue: period) ?? .thisWeek }

    var selection: ShareSelection {
        var s = ShareSelection()
        s.showName = showName; s.counts = counts; s.purposes = purposes; s.feelings = feelings; s.apps = apps ?? true; s.restriction = restriction ?? false
        s.phrase = phraseId.flatMap(SharePhrase.init(rawValue:))
        s.message = message ?? ""
        return s
    }

    /// 前回の更新から、一定時間（既定1時間）がたっていれば、更新する時期。
    func isDue(now: Date, minimumInterval: TimeInterval = 3_600) -> Bool {
        now.timeIntervalSince(lastRefreshedAt) >= minimumInterval
    }
}

protocol StandingShareStoring: AnyObject {
    func load(uid: String) -> [StandingShareConfig]
    func save(_ configs: [StandingShareConfig], uid: String)
}

/// 端末内（UserDefaults）の保管。アカウントごとに分ける。統計やトークンは入れない。
final class UserDefaultsStandingStore: StandingShareStoring {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ uid: String) -> String { "standing.shares.\(uid)" }

    func load(uid: String) -> [StandingShareConfig] {
        defaults.data(forKey: key(uid)).flatMap { try? JSONDecoder().decode([StandingShareConfig].self, from: $0) } ?? []
    }

    func save(_ configs: [StandingShareConfig], uid: String) {
        if configs.isEmpty { defaults.removeObject(forKey: key(uid)) } else if let data = try? JSONEncoder().encode(configs) { defaults.set(data, forKey: key(uid)) }
    }
}

/// フレンドから届いた記録の「見た」の控え（この端末だけ）。新しい記録・更新があるとき、バッジを出すために使う。
/// 共有ごとに、見た時点の版（更新時刻）を覚え、版が変わったら、もう一度「新しい」になる。
struct SeenRecords: Codable, Equatable {
    private(set) var versions: [String: String] = [:]

    func isUnseen(id: String, version: String) -> Bool { versions[id] != version }

    mutating func markSeen(id: String, version: String) { versions[id] = version }

    /// 届かなくなった共有（期限切れ・停止・フレンド解除）の控えを捨てる。
    mutating func prune(keeping ids: Set<String>) { versions = versions.filter { ids.contains($0.key) } }
}

final class SeenRecordsStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ uid: String) -> String { "seen.records.\(uid)" }

    func load(uid: String) -> SeenRecords {
        defaults.data(forKey: key(uid)).flatMap { try? JSONDecoder().decode(SeenRecords.self, from: $0) } ?? SeenRecords()
    }

    func save(_ seen: SeenRecords, uid: String) {
        if let data = try? JSONEncoder().encode(seen) { defaults.set(data, forKey: key(uid)) }
    }

    func clear(uid: String) { defaults.removeObject(forKey: key(uid)) }
}
