import Foundation
import Observation

/// 1つの待機Sessionの時間管理。前面（active）の区間だけ進む。
/// 呼び出し側（View）は `activate()` / `tick()` / `deactivate()` を呼ぶだけでよい。
@MainActor
@Observable
final class WaitController {
    private(set) var remaining: TimeInterval
    private(set) var isFinished = false

    @ObservationIgnored private var countdown: WaitCountdown
    @ObservationIgnored private let session: Session
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private let clock: MonotonicClock

    init(session: Session, store: SessionStore, clock: MonotonicClock = SystemMonotonicClock()) {
        self.session = session
        self.store = store
        self.clock = clock
        self.countdown = WaitCountdown(remaining: session.remainingWaitSeconds)
        self.remaining = countdown.remaining
        self.isFinished = session.phase != .waiting
    }

    var progress: Double {
        let total = session.requiredWaitSeconds
        guard total > 0 else { return 1 }
        return min(1, max(0, 1 - remaining / total))
    }

    /// 描画用の現在の残り時間。時計から直接求めるので、ティックの間も滑らかに減る。
    func liveRemaining() -> TimeInterval {
        guard !isFinished else { return 0 }
        return countdown.remaining(at: clock.now())
    }

    func liveProgress() -> Double {
        let total = session.requiredWaitSeconds
        guard total > 0 else { return 1 }
        return min(1, max(0, 1 - liveRemaining() / total))
    }

    func activate() {
        guard session.phase == .waiting else { return }
        countdown.resume(at: clock.now())
    }

    func tick() {
        guard session.phase == .waiting, countdown.isRunning else { return }
        countdown.tick(at: clock.now())
        remaining = countdown.remaining
        if countdown.isFinished { finish() }
    }

    /// 非アクティブ化・画面を離れるとき。残り時間を保存する。
    func deactivate() {
        guard session.phase == .waiting else { return }
        countdown.pause(at: clock.now())
        remaining = countdown.remaining
        if countdown.isFinished {
            finish()
        } else {
            store.saveRemaining(session, seconds: countdown.remaining)
        }
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        store.markWaitFinished(session)
    }
}
