import Foundation

/// 「制限の一時停止」のルール。衝動的に、制限全体を止めにくくするための、待機つきの手順。
/// 本体と拡張（FutoMonitor）で共有する、Foundationだけの値。
struct PauseRules: Equatable {
    /// 停止の前に待つ時間（秒）。待機中も制限は続く。
    var waitSeconds: TimeInterval
    /// 実際に解除した時刻から、制限を停止しておく時間（分）。
    var pauseMinutes: Int
    /// 待機が終わってから、「停止する」を押せる期間（秒）。過ぎたら、待機をやり直す。
    var readyValidSeconds: TimeInterval = 600
    /// 待機が途中で止まったまま、この時間（秒）が過ぎたら、待機をやり直す。
    var idleResetSeconds: TimeInterval = 3600

    #if DEBUG
    /// 開発中は、確かめやすいよう待機だけ短くする（Releaseには入らない）。
    static let standard = PauseRules(waitSeconds: 15, pauseMinutes: 30)
    #else
    static let standard = PauseRules(waitSeconds: 600, pauseMinutes: 30)
    #endif

    var pauseSeconds: TimeInterval { TimeInterval(pauseMinutes) * 60 }
}

/// 停止前の待機。前面で表示している間だけ減る（残りは、保存して再起動しても飛ばせない）。
struct PauseWait: Codable, Equatable {
    var required: TimeInterval
    var remaining: TimeInterval
    /// 最後に進んだ（または保存した）時刻。長く放置された待機を、やり直しにするために使う
    var lastActiveAt: Date
    /// 待機が終わった時刻。ここから一定時間だけ「停止する」を押せる
    var readyAt: Date?

    var isReady: Bool { remaining <= 0 && readyAt != nil }
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
