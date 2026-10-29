import SwiftData
import Foundation

struct ReflectionContent: Equatable {
    var title: String
    var lines: [String]
}

/// 朝夜の振り返りの文章。端末内の集計と定型文だけで作る（LLMは使わない）。
/// 気持ちの推測・評価・称賛はしない。取得済みの記録だけを事実として並べる。
enum ReflectionBuilder {
    /// - Parameters:
    ///   - interval: 振り返る範囲（朝は昨日、夜は今日。開発中の朝は今日）
    ///   - dayWord: 「昨日」「今日」
    static func build(kind: ReflectionKind, sessions: [Session], mode: AppMode,
                      interval: DateInterval, dayWord: String) -> ReflectionContent {
        let records = sessions.filter {
            $0.mode == mode && interval.contains($0.startedAt) && $0.phase != .choosingPurpose
        }
        guard !records.isEmpty else {
            return ReflectionContent(title: kind.title, lines: ["\(dayWord)の記録はまだありません。"])
        }

        var lines = ["\(dayWord)は、ひと呼吸を\(records.count)回おこないました。"]

        let deferred = records.filter { $0.outcome == .deferred }.count
        let wants = records.filter { $0.outcome == .wantsToUse }.count
        let interrupted = records.filter { $0.outcome == .interrupted }.count
        let outcomes = [("今はやめる", deferred), ("使いたい", wants), ("途中でやめた", interrupted)]
            .filter { $0.1 > 0 }
            .map { "\($0.0) \($0.1)回" }
        if !outcomes.isEmpty { lines.append(outcomes.joined(separator: "、") + "。") }

        let purposes = Purpose.allCases
            .map { purpose in (purpose, records.filter { $0.purpose == purpose }.count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
        if !purposes.isEmpty {
            lines.append("選んだ目的は、" + purposes.map { "「\($0.0.label)」\($0.1)回" }.joined(separator: "、") + "。")
        }

        let answers = Reflection.allCases.filter { $0 != .skipped }
            .map { r in (r, records.filter { $0.reflection == r }.count) }
            .filter { $0.1 > 0 }
        if !answers.isEmpty {
            lines.append("使ったあとの感想は、" + answers.map { "「\($0.0.label)」\($0.1)件" }.joined(separator: "、") + "。")
        }

        let unlocked = records.filter { $0.temporaryUnlockStartedAt != nil }.count
        if unlocked > 0 {
            lines.append("一時解除を始めたのは\(unlocked)回です。実際に使ったかどうかは記録していません。")
        }
        return ReflectionContent(title: kind.title, lines: lines)
    }
}

/// 朝・夜の振り返りをいつ表示するか。設定時刻から一定時間だけ、論理日の中で表示する。
enum ReflectionSchedule {
    /// 表示を続ける長さ。夜は論理日の終わり（午前4時）で必ず終わる。
    static let windowMinutes = 6 * 60

    static func isAvailable(clockMinute setting: Int, now: Date, calendar: LogicalCalendar) -> Bool {
        let start = calendar.logicalMinute(clockMinute: setting)
        let current = calendar.logicalMinute(of: now)
        return current >= start && current < min(start + windowMinutes, 1440)
    }

    /// カードに載せる記録の範囲と呼び方。朝は昨日、夜は今日。
    /// 開発中は昨日の記録が無いため、朝も今日の記録を使う（`useTodayForMorning`）。
    static func contentRange(kind: ReflectionKind, now: Date, calendar: LogicalCalendar,
                             useTodayForMorning: Bool) -> (interval: DateInterval, dayWord: String) {
        if kind == .night || useTodayForMorning {
            return (calendar.dayInterval(containing: now), "今日")
        }
        return (calendar.previousDayInterval(before: now), "昨日")
    }
}

/// 振り返りカードの保存。同じ（モード・種類・日）のカードは作り直さない。
@MainActor
final class ReflectionCardStore {
    let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    func all() -> [ReflectionCard] {
        (try? context.fetch(FetchDescriptor<ReflectionCard>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    func card(mode: AppMode, kind: ReflectionKind, dayKey: String) -> ReflectionCard? {
        let key = ReflectionCard.makeKey(mode: mode, kind: kind, dayKey: dayKey)
        return all().first { $0.key == key }
    }

    /// 既にあればそのまま返す。無ければ内容を作って保存する。
    /// `regenerate` は開発用ボタンのときだけ true（作り直して未読扱いに戻す）。
    @discardableResult
    func ensureCard(mode: AppMode, kind: ReflectionKind, dayKey: String,
                    content: @autoclosure () -> ReflectionContent, regenerate: Bool = false) -> ReflectionCard {
        if let existing = card(mode: mode, kind: kind, dayKey: dayKey) {
            guard regenerate else { return existing }
            context.delete(existing)
        }
        let built = content()
        let card = ReflectionCard(mode: mode, kind: kind, dayKey: dayKey, title: built.title,
                                  lines: built.lines, createdAt: now())
        context.insert(card)
        try? context.save()
        return card
    }

    func dismiss(_ card: ReflectionCard) {
        guard card.dismissedAt == nil else { return }
        card.dismissedAt = now()
        try? context.save()
    }

    func deleteAll() {
        for card in all() { context.delete(card) }
        try? context.save()
    }
}
