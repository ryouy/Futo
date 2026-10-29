import Foundation
import SwiftData

enum ReflectionKind: String, Codable, CaseIterable {
    case morning
    case night

    var title: String { self == .morning ? tr("朝の振り返り") : tr("夜の振り返り") }
}

/// 朝・夜に表示した振り返りカード。保存して、起動のたびに作り直さない。
/// 同じ（モード・種類・日）のカードは1枚だけ。
@Model
final class ReflectionCard {
    @Attribute(.unique) var key: String
    var mode: AppMode
    var kind: ReflectionKind
    /// 表示した日（深夜は前日として数える論理日）
    var dayKey: String
    var title: String
    /// 本文（1行ずつ改行で区切る）
    var body: String
    var createdAt: Date
    var dismissedAt: Date?

    init(mode: AppMode, kind: ReflectionKind, dayKey: String, title: String, lines: [String], createdAt: Date) {
        self.key = ReflectionCard.makeKey(mode: mode, kind: kind, dayKey: dayKey)
        self.mode = mode
        self.kind = kind
        self.dayKey = dayKey
        self.title = title
        self.body = lines.joined(separator: "\n")
        self.createdAt = createdAt
        self.dismissedAt = nil
    }

    var lines: [String] { body.split(separator: "\n").map(String.init) }

    static func makeKey(mode: AppMode, kind: ReflectionKind, dayKey: String) -> String {
        "\(mode.rawValue)|\(kind.rawValue)|\(dayKey)"
    }
}
