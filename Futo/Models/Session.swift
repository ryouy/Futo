import Foundation
import SwiftData

/// 動作モード。デモと実機の記録・設定は混ぜない。
enum AppMode: String, Codable, CaseIterable {
    case demo
    case device
}

/// 目的。表示文言は `label` に分離し、保存は列挙値のみ。
enum Purpose: String, Codable, CaseIterable, Identifiable {
    case contact
    case research
    case change = "break"
    case noReason

    var id: String { rawValue }

    var label: String {
        switch self {
        case .contact: return "連絡"
        case .research: return "調べもの"
        case .change: return "気分転換"
        case .noReason: return "なんとなく"
        }
    }
}

enum SessionPhase: String, Codable {
    case choosingPurpose
    case waiting
    case awaitingChoice
    case completed
    case interrupted

    var isOpen: Bool {
        switch self {
        case .choosingPurpose, .waiting, .awaitingChoice: return true
        case .completed, .interrupted: return false
        }
    }
}

enum SessionOutcome: String, Codable {
    case deferred
    case wantsToUse
    case interrupted

    var label: String {
        switch self {
        case .deferred: return "今はやめる"
        case .wantsToUse: return "使いたい"
        case .interrupted: return "中断"
        }
    }
}

/// 一時解除で使ったあとの感想。評価ではなく、本人の感覚を残すためのもの。
enum Reflection: String, Codable, CaseIterable {
    case satisfied
    case neutral
    case wishedLess
    /// 答えなかった。再び尋ねないための印
    case skipped

    var label: String {
        switch self {
        case .satisfied: return "満足した"
        case .neutral: return "どちらでもない"
        case .wishedLess: return "もう少し控えたかった"
        case .skipped: return "答えない"
        }
    }
}

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var mode: AppMode
    var startedAt: Date
    /// nil は未回答（スキップ）
    var purpose: Purpose?
    var requiredWaitSeconds: Double
    var remainingWaitSeconds: Double
    var phase: SessionPhase
    /// nil は未確定
    var outcome: SessionOutcome?
    var completedAt: Date?
    /// 実機で一時解除を開始できた場合だけ記録する。手動の制限終了は含めない。
    var temporaryUnlockStartedAt: Date?
    /// 一時解除が終わった（再制限された）時刻。解除していた時間の算出に使う。nil は解除中、または不明
    var temporaryUnlockEndedAt: Date?
    /// 一時解除したアプリ。OSの不透明なトークンをそのまま保存し、名前やbundle IDは保存しない（履歴で表示用に復元する）。
    var temporaryUnlockedApps: Data?
    /// 一時解除のあとに答えた感想。nil は未回答（まだ尋ねていない）
    var reflection: Reflection?

    init(mode: AppMode, startedAt: Date, requiredWaitSeconds: Double) {
        self.id = UUID()
        self.mode = mode
        self.startedAt = startedAt
        self.purpose = nil
        self.requiredWaitSeconds = requiredWaitSeconds
        self.remainingWaitSeconds = requiredWaitSeconds
        self.phase = .choosingPurpose
        self.outcome = nil
        self.completedAt = nil
        self.temporaryUnlockStartedAt = nil
        self.temporaryUnlockEndedAt = nil
        self.reflection = nil
        self.temporaryUnlockedApps = nil
    }
}
