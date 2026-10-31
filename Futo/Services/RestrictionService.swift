import Foundation
import SwiftData

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
    /// 制限全体を一時停止中（実機のみ）。区間が終わると、拡張が停止前の制限へ戻す
    case paused(until: Date)
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

// MARK: デモ（Appetize 公開用）

/// コンパイル条件 `FUTO_DEMO` のビルドだけ有効になるデモ。通常のビルドでは常に false。
/// デモでは、Screen Time・ログイン・課金・広告を一切使わない。待機は10秒、記録はサンプル。
enum DemoConfig {
    #if FUTO_DEMO
    static let isOn = true
    #else
    static let isOn = false
    #endif
}

/// デモに出てくるアプリ。名前とアイコン（記号と色）だけを持つ。
struct DemoApp: Identifiable, Hashable {
    let name: String
    let symbol: String
    let top: UInt32
    let bottom: UInt32
    var id: String { name }

    static let catalog = [
        DemoApp(name: "Vidly", symbol: "play.fill", top: 0xFF5F6D, bottom: 0xD6264A),
        DemoApp(name: "Chatter", symbol: "bubble.left.and.bubble.right.fill", top: 0x4FB0FF, bottom: 0x2B5FDB),
        DemoApp(name: "Puzzle Quest", symbol: "puzzlepiece.extension.fill", top: 0xFFB347, bottom: 0xE5532D),
    ]

    static func named(_ name: String) -> DemoApp? { catalog.first { $0.name == name } }
}

/// デモ用。Screen Timeを一切呼ばず、実際のアプリも制限しない。保存は端末内のメモリだけ。
@MainActor
final class DemoRestrictionService: RestrictionService {
    private(set) var targets: [String] = DemoApp.catalog.map(\.name)
    private var intent = true

    var permission: PermissionState { .approved }
    var targetCount: Int { targets.count }
    var intendsRestriction: Bool { intent }
    var supportsTemporaryUnlock: Bool { false }

    func setTarget(_ name: String, selected: Bool) {
        if selected, !targets.contains(name) { targets.append(name) }
        if !selected { targets.removeAll { $0 == name } }
        if targets.isEmpty { intent = false }
    }

    func refreshPermission() {}
    func requestPermission() async -> String? { nil }
    func start() { if !targets.isEmpty { intent = true } }

    @discardableResult
    func stop() -> Bool { intent = false; return true }

    func relock() {}
    func verify() -> RestrictionState { intent && !targets.isEmpty ? .configured : .off }
}

/// デモの初回に入れるサンプルの記録（過去2週間ぶん）。
@MainActor
enum DemoSeed {
    static func populate(context: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        // (何日前, 時, 分, 目的, 結果, 解除した分, 感想)
        let rows: [(Int, Int, Int, Purpose?, SessionOutcome, Int?, Reflection?)] = [
            (0, 8, 40, .contact, .deferred, nil, nil),
            (0, 12, 15, .noReason, .deferred, nil, nil),
            (1, 7, 55, .noReason, .deferred, nil, nil),
            (1, 13, 20, .research, .wantsToUse, 5, .satisfied),
            (1, 22, 5, .change, .deferred, nil, nil),
            (2, 9, 10, .contact, .wantsToUse, 5, .neutral),
            (2, 18, 45, .noReason, .deferred, nil, nil),
            (3, 12, 30, .change, .deferred, nil, nil),
            (3, 23, 10, .noReason, .wantsToUse, 5, .wishedLess),
            (4, 8, 5, .noReason, .deferred, nil, nil),
            (4, 19, 20, .research, .wantsToUse, 5, .satisfied),
            (5, 14, 0, .change, .deferred, nil, nil),
            (6, 10, 30, .noReason, .deferred, nil, nil),
            (6, 21, 40, .noReason, .wantsToUse, 5, .wishedLess),
            (8, 11, 15, .contact, .wantsToUse, 5, .satisfied),
            (9, 15, 50, .change, .deferred, nil, nil),
            (10, 20, 25, .noReason, .deferred, nil, nil),
            (12, 9, 0, .research, .deferred, nil, nil),
            (13, 17, 35, .noReason, .wantsToUse, 5, .neutral),
        ]
        for row in rows {
            guard let day = cal.date(byAdding: .day, value: -row.0, to: now),
                  var start = cal.date(bySettingHour: row.1, minute: row.2, second: 0, of: day) else { continue }
            if start > now { start = now.addingTimeInterval(-3600) }
            let session = Session(mode: .demo, startedAt: start, requiredWaitSeconds: 10)
            session.purpose = row.3
            session.remainingWaitSeconds = 0
            session.phase = .completed
            session.outcome = row.4
            session.completedAt = start.addingTimeInterval(14)
            if let minutes = row.5 {
                session.temporaryUnlockStartedAt = start.addingTimeInterval(20)
                session.temporaryUnlockEndedAt = start.addingTimeInterval(20 + Double(minutes) * 60)
                session.reflection = row.6
            }
            context.insert(session)
        }
        if let day = cal.date(byAdding: .day, value: -4, to: now) {
            context.insert(RestrictionEvent(mode: .demo, kind: .pause, at: day, minutes: 10))
        }
        try? context.save()
    }
}
