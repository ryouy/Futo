import Foundation

#if DEBUG
/// 開発用：起動の引数（`-futoScreen settings-notify` など）で、確かめたい画面を、すぐ開く（シミュレーターでの表示確認用）。
/// Debugビルドにだけ存在する。
enum DebugLaunch {
    static var screen: String? { UserDefaults.standard.string(forKey: "futoScreen") }
    static var onboardingPage: Int { UserDefaults.standard.integer(forKey: "futoOnboardingPage") }

    static var settingsTabIndex: Int? {
        switch screen {
        case "settings-restriction": return 0
        case "settings-notify": return 1
        case "settings-account": return 2
        case "settings-other": return 3
        default: return nil
        }
    }
}
#endif
