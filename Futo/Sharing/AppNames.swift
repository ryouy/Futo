import FamilyControls
import Foundation
import ManagedSettings

/// 選択画面（FamilyActivityPicker）が返したときだけ、名前が読める。トークンだけからは、読めないことが多い。
/// そこで、選んで保存した時点の名前を、この端末にだけ控えておく（共有で名前を出すときに使う）。
enum AppNameStore {
    private static let defaultsKey = "device.itemNames"

    private static func key<T: Encodable>(_ token: T) -> String? {
        (try? JSONEncoder().encode(token)).map { $0.base64EncodedString() }
    }

    private static func load() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
    }

    static func name(for item: RestrictedItem) -> String? {
        let names = load()
        switch item {
        case .app(let token): return key(token).flatMap { names[$0] }
        case .category(let token): return key(token).flatMap { names[$0] }
        case .web(let token): return key(token).flatMap { names[$0] }
        }
    }

    /// 選択に含まれる、名前の読めるものを控える。読めないものは、前の控えをそのまま残す。
    static func record(_ selection: FamilyActivitySelection) {
        var names = load()
        for app in selection.applications {
            if let token = app.token, let name = app.localizedDisplayName, !name.isEmpty, let k = key(token) { names[k] = name }
        }
        for category in selection.categories {
            if let token = category.token, let name = category.localizedDisplayName, !name.isEmpty, let k = key(token) { names[k] = name }
        }
        for web in selection.webDomains {
            if let token = web.token, let name = web.domain, !name.isEmpty, let k = key(token) { names[k] = name }
        }
        UserDefaults.standard.set(names, forKey: defaultsKey)
    }
}

/// 解除した対象（アプリ・カテゴリ・ウェブサイト）の名前を、OSのAPIから読み取る。
/// 記録には名前を保存していない（OSが発行する不透明なトークンだけ）ので、共有するときに、その場で読み取る。
/// 読み取れるかどうかはOSと許可の状態に依存する。読み取れない対象は、名前を推測せず、共有に含めない。
enum AppNameResolver {
    static func name(for item: RestrictedItem) -> String? {
        if let stored = AppNameStore.name(for: item), !stored.isEmpty { return stored }
        switch item {
        case .app(let token): return Application(token: token).localizedDisplayName
        case .category(let token): return ActivityCategory(token: token).localizedDisplayName
        case .web(let token): return WebDomain(token: token).domain
        }
    }

    private static func keys(_ session: Session) -> [RestrictedItem] {
        RestrictedItems.decode(session.temporaryUnlockedApps).sortedItems
    }

    /// 共有用：期間ごとの、名前つきの回数。
    static func counts(sessions: [Session], mode: AppMode) -> (DateInterval) -> [AppCount] {
        { interval in
            AppUsageSummary.top(sessions: sessions, mode: mode, interval: interval, keys: keys, name: name(for:))
        }
    }

    /// 期間内に解除した対象の数と、そのうち名前を読み取れた数（画面で、取れなかった理由を正直に伝えるため）。
    static func availability(sessions: [Session], mode: AppMode, interval: DateInterval?) -> (total: Int, named: Int) {
        var items = Set<RestrictedItem>()
        for session in sessions {
            guard session.mode == mode, session.phase == .completed, session.outcome == .wantsToUse,
                  let at = session.temporaryUnlockStartedAt else { continue }
            if let interval, !interval.contains(at) { continue }
            items.formUnion(keys(session))
        }
        return (items.count, items.filter { name(for: $0).flatMap(AppUsageSummary.cleanName) != nil }.count)
    }
}
