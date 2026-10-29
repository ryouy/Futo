import Foundation

/// 単調増加する時計の値（秒）を返す。テストでは差し替える。
protocol MonotonicClock {
    func now() -> TimeInterval
}

struct SystemMonotonicClock: MonotonicClock {
    func now() -> TimeInterval { ProcessInfo.processInfo.systemUptime }
}

/// 待機の残り時間。Timerの呼び出し回数ではなく、時計の差分で減らす。
/// 実行中（resume〜pause）の区間だけ経過する。
struct WaitCountdown {
    private(set) var remaining: TimeInterval
    private var lastTick: TimeInterval?

    init(remaining: TimeInterval) {
        self.remaining = max(0, remaining)
    }

    var isRunning: Bool { lastTick != nil }
    var isFinished: Bool { remaining <= 0 }

    mutating func resume(at now: TimeInterval) {
        guard lastTick == nil else { return }
        lastTick = now
    }

    mutating func tick(at now: TimeInterval) {
        guard let last = lastTick else { return }
        remaining = max(0, remaining - max(0, now - last))
        lastTick = now
    }

    mutating func pause(at now: TimeInterval) {
        tick(at: now)
        lastTick = nil
    }
}
