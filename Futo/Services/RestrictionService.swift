import Foundation

enum PermissionState: Equatable {
    case notDetermined
    case approved
    /// 拒否、または後から取り消された状態
    case denied
}

enum RestrictionState: Equatable {
    case off
    /// 保存した意図と、本アプリ用ストアの内容が一致している
    case configured
    /// 有効にしたはずだが、権限やストアの内容から確認できない
    case unverifiable
}

/// 実機（Screen Time）とデモを差し替えるための小さな境界。
@MainActor
protocol RestrictionService: AnyObject {
    var permission: PermissionState { get }
    var targetCount: Int { get }
    /// 「制限を有効にする」意図（保存値）。有効だとは限らない。`verify()` で照合する。
    var intendsRestriction: Bool { get }

    func refreshPermission()
    /// 失敗時はユーザー向けメッセージを返す。
    func requestPermission() async -> String?
    func start()
    /// 本アプリの制限を外せたか。
    @discardableResult func stop() -> Bool
    func verify() -> RestrictionState
}
