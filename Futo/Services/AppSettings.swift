import Foundation

/// 軽量な設定。権限の有無はここに保存せず、常にOSへ確認する。
final class AppSettings {
    private enum Key {
        static let onboardingDone = "settings.onboardingDone"
        static let mode = "settings.mode"
        static let debugShortWait = "settings.debugShortWait"
    }

    static let standardWaitSeconds: Double = 180
    static let debugWaitSeconds: Double = 10

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var onboardingDone: Bool {
        get { defaults.bool(forKey: Key.onboardingDone) }
        set { defaults.set(newValue, forKey: Key.onboardingDone) }
    }

    var mode: AppMode {
        get { AppMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .demo }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    /// Debugビルドでのみ有効。Releaseでは常に false。
    var debugShortWait: Bool {
        get {
            #if DEBUG
            return defaults.bool(forKey: Key.debugShortWait)
            #else
            return false
            #endif
        }
        set { defaults.set(newValue, forKey: Key.debugShortWait) }
    }

    var waitSeconds: Double {
        debugShortWait ? Self.debugWaitSeconds : Self.standardWaitSeconds
    }
}
