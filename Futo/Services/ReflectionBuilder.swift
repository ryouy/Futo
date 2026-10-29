import SwiftData
import Foundation

struct ReflectionContent: Equatable {
    var title: String
    var lines: [String]
}

/// 朝夜の振り返りの文章。端末内の集計と定型文（プリセット）だけで作る（LLMは使わない）。
/// 数をそのまま並べず、「少なめ」「多め」「中心」のような抽象的な言い方に置き換える。
/// 気持ちの推測・評価・称賛はしない。朝は「はじまり」、夜は「ひと区切り」に合う言葉を使う。
enum ReflectionBuilder {
    private enum Volume { case few, some, many }

    /// - Parameters:
    ///   - interval: 振り返る範囲（朝は昨日、夜は今日。開発中の朝は今日）
    ///   - dayWord: 「昨日」「今日」
    ///   - seed: 同じ日・同じ記録なら同じ文言になるよう、言い回しの選択に使う（日の識別子など）
    static func build(kind: ReflectionKind, sessions: [Session], mode: AppMode,
                      interval: DateInterval, dayWord: String, seed: String = "") -> ReflectionContent {
        let records = sessions.filter {
            $0.mode == mode && interval.contains($0.startedAt) && $0.phase != .choosingPurpose
        }
        let seed = seed + kind.rawValue
        let closing = pick(closings(kind), seed, 9)
        // 朝は、どの記録を使っていても「昨日は、」で始める（開発中は今日の記録で作るため）。
        let dayWord = kind == .morning ? tr("昨日") : dayWord

        guard !records.isEmpty else {
            return ReflectionContent(title: kind.title, lines: [tr("{0}は、記録がまだありません。", "\(dayWord)"), closing])
        }

        let volume: Volume = records.count <= 2 ? .few : (records.count <= 5 ? .some : .many)
        var lines = [pick(openings(kind, volume, dayWord), seed, 1)]
        if let line = outcomeLine(records, seed) { lines.append(line) }
        if let line = purposeLine(records, seed) { lines.append(line) }
        // 詳細は多くても1行。感想があれば感想を、なければ解除の様子を言う。
        if let line = reflectionLine(records, seed) ?? unlockLine(records, seed) { lines.append(line) }
        lines.append(closing)
        return ReflectionContent(title: kind.title, lines: lines)
    }

    // MARK: プリセット

    private static func openings(_ kind: ReflectionKind, _ volume: Volume, _ day: String) -> [String] {
        switch (kind, volume) {
        case (.morning, .few):
            return [tr("{0}は、立ち止まる場面が少なめでした。", "\(day)"), tr("{0}は、ひと呼吸が少なめでした。", "\(day)")]
        case (.morning, .some):
            return [tr("{0}は、何度か立ち止まる時間がありました。", "\(day)"), tr("{0}は、ひと呼吸が何回かありました。", "\(day)")]
        case (.morning, .many):
            return [tr("{0}は、立ち止まる場面が多めでした。", "\(day)"), tr("{0}は、ひと呼吸をたくさんしました。", "\(day)")]
        case (.night, .few):
            return [tr("{0}は、立ち止まる場面が少なめでした。", "\(day)"), tr("{0}は、ひと呼吸が少なめでした。", "\(day)")]
        case (.night, .some):
            return [tr("{0}は、何度か立ち止まりました。", "\(day)"), tr("{0}は、ひと呼吸が何回かありました。", "\(day)")]
        case (.night, .many):
            return [tr("{0}は、立ち止まる場面が多めでした。", "\(day)"), tr("{0}は、ひと呼吸をたくさんしました。", "\(day)")]
        }
    }

    private static func closings(_ kind: ReflectionKind) -> [String] {
        switch kind {
        case .morning: return [tr("新しい一日のはじまりです。"), tr("今日のペースで、ゆっくり。"), tr("ゆっくり始めましょう。")]
        case .night: return [tr("今日はここまでです。"), tr("一日の終わりです。"), tr("ここでひと区切りにしましょう。")]
        }
    }

    private static func outcomeLine(_ records: [Session], _ seed: String) -> String? {
        let deferred = records.filter { $0.outcome == .deferred }.count
        let wants = records.filter { $0.outcome == .wantsToUse }.count
        let interrupted = records.count - deferred - wants
        if records.count == 1 {
            if deferred == 1 { return tr("「やめておく」を選びました。") }
            if wants == 1 { return tr("「使いたい」を選びました。") }
            return tr("途中でやめました。")
        }
        if interrupted * 2 >= records.count {
            return pick([tr("途中でやめる場面が多めでした。"), tr("途中で終えることが多めでした。")], seed, 2)
        }
        let decided = deferred + wants
        guard decided > 0 else { return nil }
        let share = Double(deferred) / Double(decided)
        if share >= 0.7 { return pick([tr("「やめておく」が多めでした。"), tr("ほとんど「やめておく」でした。")], seed, 3) }
        if share <= 0.3 { return pick([tr("「使いたい」が多めでした。"), tr("ほとんど「使いたい」でした。")], seed, 3) }
        return pick([tr("「やめておく」と「使いたい」は半々でした。"), tr("どちらも同じくらいでした。")], seed, 3)
    }

    private static func purposeLine(_ records: [Session], _ seed: String) -> String? {
        let counts = Purpose.allCases.map { p in (p, records.filter { $0.purpose == p }.count) }.filter { $0.1 > 0 }
        let answered = counts.reduce(0) { $0 + $1.1 }
        if answered == 0 {
            return records.count == 1 ? tr("目的は答えませんでした。") : tr("目的は、あまり答えませんでした。")
        }
        let top = counts.max { $0.1 < $1.1 }!
        if answered == 1 { return tr("目的は「{0}」でした。", "\(top.0.label)") }
        if Double(top.1) / Double(answered) >= 0.6 {
            return pick([tr("目的は「{0}」が中心でした。", "\(top.0.label)"), tr("目的は、おもに「{0}」でした。", "\(top.0.label)")], seed, 4)
        }
        return pick([tr("目的は、いろいろでした。"), tr("目的は、ばらけていました。")], seed, 4)
    }

    private static func reflectionLine(_ records: [Session], _ seed: String) -> String? {
        let kinds: [Reflection] = [.satisfied, .neutral, .wishedLess]
        let counts: [(Reflection, Int)] = kinds.map { r in (r, records.filter { $0.reflection == r }.count) }
        let answered = counts.reduce(0) { $0 + $1.1 }
        guard answered > 0 else { return nil }
        let top = counts.max { $0.1 < $1.1 }!
        if answered == 1 { return tr("感想は「{0}」でした。", "\(top.0.label)") }
        guard Double(top.1) / Double(answered) >= 0.6 else { return tr("感想は、分かれていました。") }
        switch top.0 {
        case .satisfied: return tr("感想は「満足した」が多めでした。")
        case .neutral: return tr("感想は「どちらでもない」が多めでした。")
        case .wishedLess: return tr("感想は「使いすぎかも」が多めでした。")
        case .skipped: return nil
        }
    }

    /// 解除していた時間（使った時間ではない）。抽象的な長さだけを言う。
    private static func unlockLine(_ records: [Session], _ seed: String) -> String? {
        let unlocked = records.filter { $0.temporaryUnlockStartedAt != nil }
        guard !unlocked.isEmpty else { return nil }
        let known = unlocked.compactMap(\.unlockDuration)
        guard !known.isEmpty else { return tr("一時的に解除した場面がありました。") }
        let minutes = known.reduce(0, +) / 60
        if minutes < 5 { return tr("解除していた時間は、短めでした。") }
        if minutes < 20 { return tr("解除していた時間は、ほどほどでした。") }
        return tr("解除していた時間は、長めでした。")
    }

    // MARK: 言い回しの選択（同じ入力なら同じ結果）

    private static func pick(_ options: [String], _ seed: String, _ salt: Int) -> String {
        let hash = seed.unicodeScalars.reduce(salt) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
        return options[hash % options.count]
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
            return (calendar.dayInterval(containing: now), tr("今日"))
        }
        return (calendar.previousDayInterval(before: now), tr("昨日"))
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
