import FamilyControls
import Foundation
import ManagedSettings

/// 一時解除の記録。本体と拡張（FutoMonitor）で共有する。
struct UnlockRecord: Codable, Equatable {
    var activityName: String
    var startedAt: Date
    var endsAt: Date
    /// 一時解除したもの（アプリ・カテゴリ・ウェブサイト）。ホームでの表示と履歴に使う（古い記録には無いので任意）
    var unlocked: RestrictedItems?
    /// この解除を始めたひと呼吸（履歴に解除時間を書き戻すため）
    var sessionID: UUID?
    /// この解除で設定していた分数
    var minutes: Int?
}

/// 一時解除が終わった（再制限された）記録。拡張が書き、本体が履歴へ反映する。
struct UnlockEnd: Codable, Equatable {
    var sessionID: UUID
    var endedAt: Date
}

/// 本体とDevice Activity拡張が共有する状態と、再制限の処理。
/// App Groupが使えない環境では `isAvailable == false` となり、一時解除は提供しない。
enum SharedState {
    static let storeName = ManagedSettingsStore.Name("jp.futo.restriction")
    static let unlockActivityPrefix = "futo.unlock."
    static let usageEventName = "futo.usage"

    private enum Key {
        static let selection = "device.selection"
        static let intent = "device.intent"
        static let unlock = "device.unlock"
        static let unlockEnds = "device.unlockEnds"
        static let pause = "device.pause"
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

    /// 制限の一時停止（待機と、停止中の区間）。本体と拡張で共有する
    static var pauseState: PauseState? {
        get {
            guard let data = defaults.data(forKey: Key.pause) else { return nil }
            return try? JSONDecoder().decode(PauseState.self, from: data)
        }
        set {
            if let newValue, !newValue.isEmpty, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.pause)
            } else {
                defaults.removeObject(forKey: Key.pause)
            }
        }
    }

    /// 解除が終わった記録（本体が読み取って履歴に反映したら消す）
    static var unlockEnds: [UnlockEnd] {
        get {
            guard let data = defaults.data(forKey: Key.unlockEnds) else { return [] }
            return (try? JSONDecoder().decode([UnlockEnd].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty { defaults.removeObject(forKey: Key.unlockEnds); return }
            if let data = try? JSONEncoder().encode(Array(newValue.suffix(30))) { defaults.set(data, forKey: Key.unlockEnds) }
        }
    }

    /// 一時解除の記録を終わらせる。終了時刻を残してから消す（本体・拡張のどちらから呼んでもよい）。
    static func clearUnlock(at date: Date = Date()) {
        if let record = unlock, let sessionID = record.sessionID {
            unlockEnds = unlockEnds + [UnlockEnd(sessionID: sessionID, endedAt: date)]
        }
        unlock = nil
    }

    /// 以前の版が標準のUserDefaultsに保存した選択を、共有側へ一度だけ移す。
    static func migrateFromStandardIfNeeded() {
        guard isAvailable, loadSelection() == nil,
              let old = loadSelection(from: .standard) else { return }
        saveSelection(old)
        defaults.set(UserDefaults.standard.bool(forKey: Key.intent), forKey: Key.intent)
    }

    // MARK: シールド（本アプリ専用ストア）

    /// 制限するものを、本アプリ専用ストアへ反映する。`unlocked` に含まれるものは外す。
    /// 解除したアプリは、制限中のカテゴリの例外にもする（カテゴリ経由で止められないように）。
    static func applyShield(items: RestrictedItems, unlocked: RestrictedItems = RestrictedItems()) {
        let store = ManagedSettingsStore(named: storeName)
        let apps = items.apps.subtracting(unlocked.apps)
        let categories = items.categories.subtracting(unlocked.categories)
        let webs = items.webDomains.subtracting(unlocked.webDomains)
        store.shield.applications = apps.isEmpty ? nil : apps
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories, except: unlocked.apps)
        store.shield.webDomains = webs.isEmpty ? nil : webs
    }

    static func clearShield() {
        let store = ManagedSettingsStore(named: storeName)
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        store.shield.webDomains = nil
    }

    /// 本アプリのストアの中身が、期待する制限と一致しているか。OS上でシールドが出ているかまでは確認できない。
    static func shieldMatches(items: RestrictedItems, unlocked: RestrictedItems = RestrictedItems()) -> Bool {
        let store = ManagedSettingsStore(named: storeName)
        var categories: Set<ActivityCategoryToken> = []
        if let policy = store.shield.applicationCategories, case .specific(let tokens, _) = policy {
            categories = tokens
        }
        let currentApps: Set<ApplicationToken> = store.shield.applications ?? []
        let currentWebs: Set<WebDomainToken> = store.shield.webDomains ?? []
        let expectedApps = items.apps.subtracting(unlocked.apps)
        let expectedCategories = items.categories.subtracting(unlocked.categories)
        let expectedWebs = items.webDomains.subtracting(unlocked.webDomains)
        if currentApps != expectedApps { return false }
        if categories != expectedCategories { return false }
        return currentWebs == expectedWebs
    }

    /// ストアに何も残っていないか。
    static var isShieldEmpty: Bool {
        let store = ManagedSettingsStore(named: storeName)
        return store.shield.applications == nil && store.shield.applicationCategories == nil && store.shield.webDomains == nil
    }

    // MARK: 再制限

    /// 現在有効な一時解除に対応するイベントか。古い・重複したイベントは無視するために使う。
    static func isCurrentUnlock(_ activityName: String) -> Bool {
        unlock?.activityName == activityName
    }

    /// 保存済みの対象を本アプリ専用ストアへ再適用し、一時解除の記録を消す。
    @discardableResult
    static func relock(reason: String) -> Bool {
        // 全体の一時停止中は、一時解除の古いイベントで、停止の状態を上書きしない
        if pauseState?.window != nil {
            return false
        }
        guard intendsRestriction,
              let selection = loadSelection(), !RestrictedItems(selection: selection).isEmpty else {
            clearUnlock()
            return false
        }
        applyShield(items: RestrictedItems(selection: selection))
        clearUnlock()
        return true
    }
}

// MARK: 制限の一時停止からの再制限

extension SharedState {
    /// 一時停止の区間を終え、停止前の制限へ戻す。拡張（Device Activity）と本体の両方から呼ぶ。
    /// 現在の区間に対応する名前のときだけ動く（延長で置き換えられた古い区間のイベントは無視する）。
    @discardableResult
    static func relockFromPause(activityName: String?, reason: String) -> Bool {
        guard var state = pauseState, let window = state.window else { return false }
        if let activityName, !state.isCurrentWindow(activityName) {
            return false
        }
        let items = (try? JSONDecoder().decode(RestrictedItems.self, from: window.itemsData))
            ?? loadSelection().map { RestrictedItems(selection: $0) }
            ?? RestrictedItems()
        guard intendsRestriction, !items.isEmpty else {
            state.window = nil
            pauseState = state
            return false
        }
        applyShield(items: items)
        state.window = nil
        pauseState = state
        return true
    }
}
