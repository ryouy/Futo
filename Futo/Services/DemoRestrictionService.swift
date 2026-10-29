import Foundation

/// デモ用。Screen Timeを一切呼ばず、実際のアプリも制限しない。
/// 保存値は実機用と別キー。実機へ切り替えても引き継がない。
@MainActor
final class DemoRestrictionService: RestrictionService {
    static let fictionalApps = ["動画アプリ（架空）", "SNSアプリ（架空）", "ゲームアプリ（架空）"]

    private enum Key {
        static let target = "demo.target"
        static let intent = "demo.intent"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// デモには権限がない。常に利用可能として扱う。
    var permission: PermissionState { .approved }
    var targetName: String? { defaults.string(forKey: Key.target) }
    var targetCount: Int { targetName == nil ? 0 : 1 }
    var intendsRestriction: Bool { defaults.bool(forKey: Key.intent) }

    func selectTarget(_ name: String?) {
        defaults.set(name, forKey: Key.target)
        if name == nil { defaults.set(false, forKey: Key.intent) }
    }

    func refreshPermission() {}
    func requestPermission() async -> String? { nil }

    func start() {
        guard targetCount > 0 else { return }
        defaults.set(true, forKey: Key.intent)
    }

    @discardableResult
    func stop() -> Bool {
        defaults.set(false, forKey: Key.intent)
        return true
    }

    func verify() -> RestrictionState {
        intendsRestriction && targetCount > 0 ? .configured : .off
    }
}
