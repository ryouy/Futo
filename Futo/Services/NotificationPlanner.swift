import Foundation

struct NotificationCandidate: Equatable {
    var kind: NotificationKind
    /// 通知の識別子。同じ予定を重複して作らないために使う
    var id: String
    var fireDate: Date
}

/// 通知の上限・間隔・静かな時間・重複防止。機能ごとに別々に予約せず、すべてここを通す。
struct NotificationPolicy {
    var maxPerDay = 4
    var minimumGap: TimeInterval = 3 * 3600
    var quietStartMinute = 22 * 60
    var quietEndMinute = 8 * 60
    var perKindDailyMax: [NotificationKind: Int] = [.postUse: 1]
    var calendar: Calendar = .current

    /// 採用の優先順。利用後の確認は、朝夜の通知と近いときは追加しない。
    static let priority: [NotificationKind] = [.night, .morning, .outing, .postUse]

    func isQuiet(_ date: Date) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        if quietStartMinute == quietEndMinute { return false }
        if quietStartMinute < quietEndMinute { return minute >= quietStartMinute && minute < quietEndMinute }
        return minute >= quietStartMinute || minute < quietEndMinute
    }
}

enum NotificationDropReason: Equatable {
    case quietHours
    case tooCloseToAnother
    case dailyLimit
    case kindDailyLimit
    case duplicate
}

enum NotificationPlanner {
    struct Result {
        var accepted: [NotificationCandidate]
        var dropped: [(candidate: NotificationCandidate, reason: NotificationDropReason)]
    }

    /// 候補から、制約を満たすものだけを選ぶ。静かな時間の通知は、翌朝にまとめて送らず取りやめる。
    static func select(_ candidates: [NotificationCandidate], policy: NotificationPolicy) -> Result {
        var accepted: [NotificationCandidate] = []
        var dropped: [(NotificationCandidate, NotificationDropReason)] = []
        let ordered = candidates.sorted { a, b in
            let ia = NotificationPolicy.priority.firstIndex(of: a.kind) ?? 99
            let ib = NotificationPolicy.priority.firstIndex(of: b.kind) ?? 99
            return ia != ib ? ia < ib : a.fireDate < b.fireDate
        }
        for candidate in ordered {
            if accepted.contains(where: { $0.id == candidate.id }) {
                dropped.append((candidate, .duplicate)); continue
            }
            if policy.isQuiet(candidate.fireDate) {
                dropped.append((candidate, .quietHours)); continue
            }
            let day = policy.calendar.startOfDay(for: candidate.fireDate)
            let sameDay = accepted.filter { policy.calendar.startOfDay(for: $0.fireDate) == day }
            if let limit = policy.perKindDailyMax[candidate.kind],
               sameDay.filter({ $0.kind == candidate.kind }).count >= limit {
                dropped.append((candidate, .kindDailyLimit)); continue
            }
            if sameDay.count >= policy.maxPerDay {
                dropped.append((candidate, .dailyLimit)); continue
            }
            if accepted.contains(where: { abs($0.fireDate.timeIntervalSince(candidate.fireDate)) < policy.minimumGap }) {
                dropped.append((candidate, .tooCloseToAnother)); continue
            }
            accepted.append(candidate)
        }
        return Result(accepted: accepted.sorted { $0.fireDate < $1.fireDate },
                      dropped: dropped.map { (candidate: $0.0, reason: $0.1) })
    }

    /// 今日と明日の分の、繰り返しの候補（朝・夜・外出）。すでに見た振り返りの通知は作らない。
    /// - Parameter viewed: 見た（カードを表示した）振り返りの "kind.dayKey"
    static func recurring(preferences: Preferences, now: Date, calendar: LogicalCalendar,
                          viewed: Set<String>) -> [NotificationCandidate] {
        var result: [NotificationCandidate] = []
        let today = calendar.calendar.startOfDay(for: now)
        for offset in 0...1 {
            guard let day = calendar.calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            func add(_ kind: NotificationKind, minute: Int) {
                guard let fire = calendar.date(on: day, clockMinute: minute), fire > now.addingTimeInterval(30) else { return }
                let dayKey = calendar.dayKey(for: fire)
                if kind == .morning || kind == .night, viewed.contains("\(kind.rawValue).\(dayKey)") { return }
                result.append(NotificationCandidate(kind: kind, id: "futo.\(kind.rawValue).\(dayKey)", fireDate: fire))
            }
            if preferences.notifyMorning { add(.morning, minute: preferences.morningMinute) }
            if preferences.notifyNight { add(.night, minute: preferences.nightMinute) }
            if preferences.notifyOuting {
                // お出かけのおすすめ：1日の回数だけ決め、時刻は、日ごとにランダム（ただし均等に離す）
                let window = OutingSchedule.window(preferences: preferences)
                let dayKey = calendar.dayKey(for: day)
                for (index, minute) in OutingSchedule.minutes(count: preferences.outingPerDay, dayKey: dayKey, window: window).enumerated() {
                    guard let fire = calendar.date(on: day, clockMinute: minute), fire > now.addingTimeInterval(30) else { continue }
                    result.append(NotificationCandidate(kind: .outing, id: "futo.outing.\(dayKey).\(index)", fireDate: fire))
                }
            }
        }
        return result
    }

    /// 設定画面に出す、間引きの知らせ（朝と夜の通知が、3時間以内のとき）。
    static func warnings(preferences: Preferences, calendar: Calendar = .current) -> [String] {
        let gap = Int(NotificationPolicy().minimumGap / 60)
        guard preferences.notifyMorning, preferences.notifyNight else { return [] }
        let distance = abs(preferences.nightMinute - preferences.morningMinute)
        return distance < gap ? [tr("{0}と{1}は3時間以内のため、どちらかを間引きます。", tr("朝の振り返り"), tr("夜の振り返り"))] : []
    }
}

/// お出かけのおすすめの時刻。回数だけ決めて、時刻は、日ごとにランダム。ただし、できるだけ均等になるよう、
/// 1日の時間帯を回数で等分した、それぞれの枠の中でずらす。朝夜の通知とは、3時間あける。
/// 同じ日は、何度予約し直しても、同じ時刻になる（日付から決めるので、再予約で動かない）。
enum OutingSchedule {
    static let earliestMinute = 9 * 60
    static let latestMinute = 20 * 60
    static let gapMinutes = 180
    static let maxJitterMinutes = 60

    /// 使える時間帯。朝・夜の通知がオンなら、その前後3時間をあける。
    static func window(preferences: Preferences) -> (start: Int, end: Int) {
        var start = earliestMinute
        var end = latestMinute
        if preferences.notifyMorning { start = max(start, preferences.morningMinute + gapMinutes) }
        if preferences.notifyNight { end = min(end, preferences.nightMinute - gapMinutes) }
        if end <= start { return (earliestMinute, latestMinute) }
        return (start, end)
    }

    /// その日の時刻（0時からの分）。回数は、時間帯に収まる最大数に抑える（3時間あけるため）。
    static func minutes(count: Int, dayKey: String, window: (start: Int, end: Int)) -> [Int] {
        let length = window.end - window.start
        let n = max(1, min(count, max(1, length / gapMinutes)))
        let slot = Double(length) / Double(n)
        let jitter = min(max(0, (slot - Double(gapMinutes)) / 2), Double(maxJitterMinutes))
        var generator = SeededGenerator(seed: dayKey)
        return (0..<n).map { index in
            let center = Double(window.start) + slot * (Double(index) + 0.5)
            let offset = jitter == 0 ? 0 : Double.random(in: -jitter...jitter, using: &generator)
            return Int((center + offset).rounded())
        }
    }
}

/// 同じ文字列から、いつも同じ並びになる乱数（SplitMix64）。
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        state = hash
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

/// お出かけの通知の文言。のんびりした誘いかけだけで、評価・不安・連続記録のような言葉は使わない。
enum OutingMessages {
    static var all: [String] {
        rawMessages.map { tr($0) }
    }

    /// 日本語の元の文言（英訳のキー）。
    static let rawMessages: [String] = [
        "外の空気を、少し吸いに行きませんか。",
        "窓の向こうは、どんな天気でしょう。",
        "温かい飲み物を用意して、ひと息。",
        "肩の力を抜いて、楽な姿勢に。",
        "いつもと違う道に、小さな発見があるかもしれません。",
        "近くの木や花。季節は少し進んだでしょうか。",
        "水を一杯。飲んでから考えてもよさそうです。",
        "少し目を閉じて、何もしない時間を。",
        "今日の空は、何色に見えますか。",
        "近所をひとまわり。行き先は決めなくても。",
        "好きな曲を一曲、聴くだけの時間に。",
        "読みかけの本を、数ページだけ。",
        "紙に、今の気持ちをひと言書いてみるのも。",
        "気になっていた場所を、ひとつだけ片づけませんか。",
        "何か食べたいものはありますか。次のごはんを考える時間に。",
        "手を洗って、気分を切り替えてみませんか。",
        "足の裏を床につけて、少し背すじを伸ばしてみましょう。",
        "遠くの景色に、ゆっくり目を向けて。",
        "今、どんな音が聞こえていますか。",
        "部屋の明るさ、今の気分に合っていますか。",
        "好きな香りがあれば、そばに置いてひと息。",
        "植物の様子を、ちょっと見てみましょうか。",
        "机の上に、少しだけ余白を。",
        "落書きでも、丸を描くだけでも。紙とペンで少し遊んでみませんか。",
        "誰かと話したい気分なら、ひと言声をかけてみるのも。",
        "最近おいしかったものを、ひとつ思い出してみて。",
        "次の休みにしたいこと。ひとつ浮かべるだけでも。",
        "何も思いつかなければ、ぼんやりしていても大丈夫。",
        "今は、新しいことを始めずに休むのもよさそうです。",
        "このまま画面を閉じて、のんびりするのもひとつ。",
        "やりかけのことに、少しだけ戻ってみますか。",
        "今日は何をして過ごしたかったんだっけ。",
        "今、体を動かしたいですか。それとも、休みたいですか。",
        "ほんの少し、何も見ない時間をつくってみるのも。",
        "ひと息ついたあとで、もう一度選べます。",
    ]

    /// 同じ予定（日・種類）なら同じ文言。日が変われば別の文言になりやすい。
    static func pick(seed: String) -> String {
        let hash = seed.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 1_000_003 }
        return all[hash % all.count]
    }
}
