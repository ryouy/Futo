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
    /// 一時解除中（実機のみ）。しきい値到達または監視区間の終了で再制限される
    case temporarilyUnlocked(until: Date)
}

enum UnlockStartResult: Equatable {
    case started(until: Date)
    /// この環境（デモ、またはApp Group未設定）では一時解除を提供しない
    case unsupported
    /// 監視を登録できなかった。解除せず、制限は続いている
    case failed
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

    var supportsTemporaryUnlock: Bool { get }
    /// 一時解除を取り消し、対象を再び制限する。
    func relock()
}
