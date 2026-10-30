import Foundation
import SwiftData

/// 制限の管理の記録：制限の一時停止と、制限の終了。解除の記録（Session）とは別に残す。
/// 開発用の解除は記録しない。時刻だけを持ち、アプリ名などは持たない。
enum RestrictionEventKind: String, Codable, CaseIterable {
    /// 制限全体を一時停止した（実際に解除した時点）
    case pause
    /// 制限そのものを終了した
    case end
}

@Model
final class RestrictionEvent {
    @Attribute(.unique) var id: UUID
    var mode: AppMode
    var kind: RestrictionEventKind
    var at: Date
    /// 一時停止の長さ（分）。終了では nil
    var minutes: Int?

    init(mode: AppMode, kind: RestrictionEventKind, at: Date, minutes: Int? = nil) {
        self.id = UUID()
        self.mode = mode
        self.kind = kind
        self.at = at
        self.minutes = minutes
    }
}

enum RestrictionEventSummary {
    struct Counts: Equatable {
        var pauses = 0
        var ends = 0
        var isEmpty: Bool { pauses == 0 && ends == 0 }
    }

    /// 期間内（`interval` が nil なら全期間）の回数。デモと実機は混ぜない。
    static func counts(_ events: [RestrictionEvent], mode: AppMode, interval: DateInterval?) -> Counts {
        var result = Counts()
        for event in events where event.mode == mode {
            if let interval, !interval.contains(event.at) { continue }
            switch event.kind {
            case .pause: result.pauses += 1
            case .end: result.ends += 1
            }
        }
        return result
    }
}

@MainActor
final class RestrictionEventStore {
    let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    func all() -> [RestrictionEvent] {
        (try? context.fetch(FetchDescriptor<RestrictionEvent>(sortBy: [SortDescriptor(\.at, order: .reverse)]))) ?? []
    }

    func record(_ kind: RestrictionEventKind, mode: AppMode, minutes: Int? = nil) {
        context.insert(RestrictionEvent(mode: mode, kind: kind, at: now(), minutes: minutes))
        try? context.save()
    }

    func deleteAll() {
        for event in all() { context.delete(event) }
        try? context.save()
    }
}
