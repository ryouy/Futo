import Foundation

/// 軽量な設定。権限の有無はここに保存せず、常にOSへ確認する。
final class AppSettings {
    private enum Key {
        static let onboardingDone = "settings.onboardingDone"
        static let mode = "settings.mode"
        static let tutorialDone = "settings.tutorialDone"
        static let preferences = "settings.preferences"
        static let suggestion = "settings.suggestion"
        static let postUse = "notif.postUse"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboardingDone: Bool {
        get { defaults.bool(forKey: Key.onboardingDone) }
        set { defaults.set(newValue, forKey: Key.onboardingDone) }
    }

    /// ホームのチュートリアルを見たか。
    var tutorialDone: Bool {
        get { defaults.bool(forKey: Key.tutorialDone) }
        set { defaults.set(newValue, forKey: Key.tutorialDone) }
    }

    var mode: AppMode {
        get { AppMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .device }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    // MARK: 設定値（JSON）

    var preferences: Preferences {
        get { load(Preferences.self, Key.preferences) ?? Preferences() }
        set { save(newValue, Key.preferences) }
    }

    var suggestionState: SuggestionState {
        get { load(SuggestionState.self, Key.suggestion) ?? SuggestionState() }
        set { save(newValue, Key.suggestion) }
    }

    /// 利用後の確認通知の予定（セッションごと）。回答したり時刻を過ぎたら取り除く。
    var postUseEntries: [PostUseEntry] {
        get { load([PostUseEntry].self, Key.postUse) ?? [] }
        set { save(newValue, Key.postUse) }
    }

    private func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

struct PostUseEntry: Codable, Equatable {
    var sessionID: UUID
    var fireDate: Date
}
