import Foundation

#if DEBUG
/// 開発用：起動の引数（`-futoScreen settings-notify` など）で、確かめたい画面を、すぐ開く（シミュレーターでの表示確認用）。
/// Debugビルドにだけ存在する。
enum DebugLaunch {
    static var screen: String? { UserDefaults.standard.string(forKey: "futoScreen") }
    /// `-futoShowTrackingExplainer YES`：広告の識別子の説明の画面だけを出す
    static var showTrackingExplainer: Bool { UserDefaults.standard.bool(forKey: "futoShowTrackingExplainer") }
    /// `-futoAskAdConsentNow YES`：広告の同意（UMP → ふとの説明 → ATT）の流れを、条件を待たずに、すぐ始める
    static var askAdConsentNow: Bool { UserDefaults.standard.bool(forKey: "futoAskAdConsentNow") }
    /// `-futoUMPGeography eea`（または `other`）：UMPの地域を、デバッグ用に指定する（同意フォームの確認用）
    static var umpGeography: String? { UserDefaults.standard.string(forKey: "futoUMPGeography") }
    /// `-futoEnterDemo YES`：共有のデモに、すぐ入る（画面の確認用）
    static var enterDemo: Bool { UserDefaults.standard.bool(forKey: "futoEnterDemo") }
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
