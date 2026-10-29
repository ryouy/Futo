import Foundation

/// 軽量な設定。権限の有無はここに保存せず、常にOSへ確認する。
final class AppSettings {
    private enum Key {
        static let onboardingDone = "settings.onboardingDone"
        static let mode = "settings.mode"
    }

    /// 待機時間。Debugビルドは開発用に10秒、Releaseは180秒。切り替え用のUIや設定はない。
    #if DEBUG
    static let waitSeconds: Double = 10
    #else
    static let waitSeconds: Double = 180
    #endif

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
}
