import FamilyControls
import Foundation
import ManagedSettings

/// 一時解除の記録。本体と拡張（FutoMonitor）で共有する。
struct UnlockRecord: Codable, Equatable {
    var activityName: String
    var startedAt: Date
    var endsAt: Date
    /// 一時解除したアプリ。ホームでの表示と履歴に使う（古い記録には無いので任意）
    var unlockedApps: Set<ApplicationToken>?
}

/// 本体とDevice Activity拡張が共有する状態と、再制限の処理。
/// App Groupが使えない環境では `isAvailable == false` となり、一時解除は提供しない。
enum SharedState {
    static let storeName = ManagedSettingsStore.Name("jp.futo.restriction")
    static let unlockActivityPrefix = "futo.unlock."
    static let usageEventName = "futo.usage"

    /// 監視区間の長さ。Appleの最短は15分のため、余裕を持たせる。区間が終わると、しきい値未達でも再制限する。
    static let unlockWindow: TimeInterval = 16 * 60
    /// 対象アプリの利用がこの分数に達したら再制限する。Debugでは検証しやすいよう1分。
    #if DEBUG
    static let unlockUsageMinutes = 1
    #else
    static let unlockUsageMinutes = 5
    #endif

    private enum Key {
        static let selection = "device.selection"
        static let intent = "device.intent"
        static let unlock = "device.unlock"
        static let lastEvent = "device.lastEvent"
    }

    /// 本体は "group.<bundle id>"、拡張は ".monitor" を除いた同じ値。entitlementsの値と一致させる。
    static var appGroupID: String {
        var id = Bundle.main.bundleIdentifier ?? ""
        if id.hasSuffix(".monitor") { id.removeLast(".monitor".count) }
        return "group." + id
    }

    static var isAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    static var defaults: UserDefaults {
        if isAvailable, let suite = UserDefaults(suiteName: appGroupID) { return suite }
        return .standard
    }

    // MARK: 保存値

    static func loadSelection(from defaults: UserDefaults = SharedState.defaults) -> FamilyActivitySelection? {
        guard let data = defaults.data(forKey: Key.selection) else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    static func saveSelection(_ selection: FamilyActivitySelection, to defaults: UserDefaults = SharedState.defaults) {
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: Key.selection) }
    }

    static var intendsRestriction: Bool {
        get { defaults.bool(forKey: Key.intent) }
        set { defaults.set(newValue, forKey: Key.intent) }
    }

    static var unlock: UnlockRecord? {
        get {
            guard let data = defaults.data(forKey: Key.unlock) else { return nil }
            return try? JSONDecoder().decode(UnlockRecord.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.unlock)
            } else {
                defaults.removeObject(forKey: Key.unlock)
            }
        }
    }

    /// 以前の版が標準のUserDefaultsに保存した選択を、共有側へ一度だけ移す。
    static func migrateFromStandardIfNeeded() {
        guard isAvailable, loadSelection() == nil,
              let old = loadSelection(from: .standard) else { return }
        saveSelection(old)
        defaults.set(UserDefaults.standard.bool(forKey: Key.intent), forKey: Key.intent)
    }

    // MARK: 検証用ログ（拡張が最後に何をしたか）

    static func log(_ text: String) {
        defaults.set("\(Date().formatted(date: .omitted, time: .standard)) \(text)", forKey: Key.lastEvent)
    }

    static var lastEvent: String? { defaults.string(forKey: Key.lastEvent) }

    // MARK: 再制限

    /// 現在有効な一時解除に対応するイベントか。古い・重複したイベントは無視するために使う。
    static func isCurrentUnlock(_ activityName: String) -> Bool {
        unlock?.activityName == activityName
    }

    /// 保存済みの対象を本アプリ専用ストアへ再適用し、一時解除の記録を消す。
    @discardableResult
    static func relock(reason: String) -> Bool {
        guard intendsRestriction,
              let selection = loadSelection(), !selection.applicationTokens.isEmpty else {
            unlock = nil
            log("再制限できませんでした（対象または意図がありません）: \(reason)")
            return false
        }
        ManagedSettingsStore(named: storeName).shield.applications = selection.applicationTokens
        unlock = nil
        log("再制限しました: \(reason)")
        return true
    }
}
