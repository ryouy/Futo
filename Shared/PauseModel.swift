import Foundation

/// 待機のあとで行う操作。どちらも、待機を省略できない。
enum WaitKind: String, Codable {
    /// 制限全体の一時停止（短い待機のあと、一定時間だけ解除する）
    case pause
    /// 制限そのものの終了（長い待機のあと、制限をはずす）
    case end
}

/// 「制限の一時停止」「制限の終了」のルール。衝動的に、制限全体を止めにくくするための、待機つきの手順。
/// 本体と拡張（FutoMonitor）で共有する、Foundationだけの値。
struct PauseRules: Equatable {
    /// 一時停止の前に待つ時間（秒）。待機中も制限は続く。
    var waitSeconds: TimeInterval
    /// 実際に解除した時刻から、制限を停止しておく時間（分）。
    var pauseMinutes: Int
    /// 制限の終了の前に待つ時間（秒）。
    var endWaitSeconds: TimeInterval = 1_800
    /// 待機が終わってから、「停止する」「終了する」を押せる期間（秒）。過ぎたら、待機をやり直す。
    var readyValidSeconds: TimeInterval = 600
    /// 待機が途中で止まったまま、この時間（秒）が過ぎたら、待機をやり直す。
    var idleResetSeconds: TimeInterval = 3600

    #if DEBUG
    /// 開発中は、確かめやすいよう待機だけ短くする（Releaseには入らない）。
    static let standard = PauseRules(waitSeconds: 10, pauseMinutes: 30, endWaitSeconds: 20)
    #else
    static let standard = PauseRules(waitSeconds: 30, pauseMinutes: 30, endWaitSeconds: 1_800)
    #endif

    var pauseSeconds: TimeInterval { TimeInterval(pauseMinutes) * 60 }

    func waitSeconds(for kind: WaitKind) -> TimeInterval {
        kind == .pause ? waitSeconds : endWaitSeconds
    }
}

/// 停止・終了の前の待機。前面で表示している間だけ減る（残りは、保存して再起動しても飛ばせない）。
struct PauseWait: Codable, Equatable {
    var kind: WaitKind = .pause
    var required: TimeInterval
    var remaining: TimeInterval
    /// 最後に進んだ（または保存した）時刻。長く放置された待機を、やり直しにするために使う
    var lastActiveAt: Date
    /// 待機が終わった時刻。ここから一定時間だけ「停止する」「終了する」を押せる
    var readyAt: Date?

    var isReady: Bool { remaining <= 0 && readyAt != nil }

    init(kind: WaitKind = .pause, required: TimeInterval, remaining: TimeInterval, lastActiveAt: Date, readyAt: Date?) {
        self.kind = kind
        self.required = required
        self.remaining = remaining
        self.lastActiveAt = lastActiveAt
        self.readyAt = readyAt
    }

    // 以前の版で保存した待機（kindがない）は、一時停止として読む。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(WaitKind.self, forKey: .kind) ?? .pause
        required = try c.decode(TimeInterval.self, forKey: .required)
        remaining = try c.decode(TimeInterval.self, forKey: .remaining)
        lastActiveAt = try c.decode(Date.self, forKey: .lastActiveAt)
        readyAt = try c.decodeIfPresent(Date.self, forKey: .readyAt)
    }
}

/// 実際に制限を停止している区間。再制限はDevice Activityの拡張が行う。
struct PauseWindow: Codable, Equatable {
    var activityName: String
    var pausedAt: Date
    var endsAt: Date
    /// 停止前に制限していたもの（RestrictedItemsをJSONにしたもの）。この内容へ戻す。
    var itemsData: Data
}

struct PauseState: Codable, Equatable {
    var wait: PauseWait?
    var window: PauseWindow?

    var isEmpty: Bool { wait == nil && window == nil }
}

extension PauseState {
    static let activityPrefix = "futo.pause."

    func isCurrentWindow(_ activityName: String) -> Bool {
        window?.activityName == activityName
    }
}
