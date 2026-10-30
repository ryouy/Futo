import Foundation
import Observation

// MARK: 境界（本体ではOS、テストでは偽物に差し替える）

protocol PauseStoring: AnyObject {
    var state: PauseState? { get set }
}

protocol PauseScheduling: AnyObject {
    /// 再制限の監視（Device Activity）が、いま登録されているか
    func isMonitoring(_ name: String) -> Bool
    /// 指定の区間の終わりに、拡張が再制限するよう登録する。失敗したら投げる
    func startWindow(name: String, from start: Date, to end: Date) throws
    /// 一時停止の監視を止める。`keep` の名前だけ残す
    func stopWindows(keeping keep: String?)
}

protocol PauseShielding: AnyObject {
    /// いま制限しているもの（JSON）。制限していなければ nil
    func currentItemsData() -> Data?
    /// 進行中の通常の一時解除を終える（監視と記録を消す）。停止が優先される
    func endOrdinaryUnlock()
    /// 制限を外す。外せたか（ストアが空か）を返す
    func relaxAll() -> Bool
    /// 停止前の制限へ戻す
    func restore(itemsData: Data)
}

enum PauseFailure: Equatable {
    /// 再制限の監視を登録できなかった（制限は外していない）
    case scheduling
    /// 制限を外せなかった（再制限は元のまま）
    case shield
    /// 制限していない、または対象がない
    case notRestricted
}

enum PauseStartResult: Equatable {
    case started(until: Date)
    /// 待機が終わっていない、または「停止する」を押せる期間を過ぎた
    case notReady
    case failed(PauseFailure)
}

/// 制限全体の一時停止の手順：待機（前面の間だけ進む）→ 本人が「停止する」→ 一定時間だけ解除 → 拡張が自動で再制限。
/// 待機の開始時点では、何も解除しない。時刻・時計は差し替えられる（テストで10分待たない）。
@MainActor
@Observable
final class PauseFlow {
    private(set) var state: PauseState?

    @ObservationIgnored private let store: PauseStoring
    @ObservationIgnored private let scheduler: PauseScheduling
    @ObservationIgnored private let shield: PauseShielding
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let clock: MonotonicClock
    @ObservationIgnored let rules: PauseRules
    @ObservationIgnored private var countdown: WaitCountdown?
    @ObservationIgnored private var lastSavedAt: TimeInterval = 0

    init(store: PauseStoring, scheduler: PauseScheduling, shield: PauseShielding,
         rules: PauseRules = .standard, now: @escaping () -> Date = Date.init, clock: MonotonicClock = SystemMonotonicClock()) {
        self.store = store
        self.scheduler = scheduler
        self.shield = shield
        self.rules = rules
        self.now = now
        self.clock = clock
        self.state = store.state
    }

    var wait: PauseWait? { state?.wait }
    var window: PauseWindow? { state?.window }
    var isPaused: Bool { window != nil }
    var isWaiting: Bool { wait != nil }

    var waitKind: WaitKind? { wait?.kind }

    /// 待機が終わっていて、「停止する」「終了する」を押せる。
    var isReady: Bool {
        guard let wait, wait.isReady, let readyAt = wait.readyAt else { return false }
        return now().timeIntervalSince(readyAt) <= rules.readyValidSeconds
    }

    // MARK: 状態の取り直し

    /// 拡張が書き換えた状態を読み直し、期限切れ・放置された待機の整理と、再制限の取りこぼしの補正をする。
    func reconcile() {
        var current = store.state
        let t = now()

        if let window = current?.window {
            let monitoring = scheduler.isMonitoring(window.activityName)
            if t >= window.endsAt || !monitoring {
                // 拡張が再制限していない場合の、安全側の補正。停止したままにしない。
                shield.restore(itemsData: window.itemsData)
                scheduler.stopWindows(keeping: nil)
                current?.window = nil
            }
        }
        if let wait = current?.wait {
            let idle = max(0, t.timeIntervalSince(wait.lastActiveAt))
            if wait.isReady, let readyAt = wait.readyAt {
                if t.timeIntervalSince(readyAt) > rules.readyValidSeconds { current?.wait = nil }
            } else if idle > rules.idleResetSeconds {
                current?.wait = nil
            }
        }
        if current != store.state { store.state = current }
        state = store.state
        if state?.wait == nil { countdown = nil }
    }

    // MARK: 待機

    /// 待機を始める（すでにあれば、そのまま続ける）。ここでは、制限を解除しない。
    /// 制限が「かかっている」ときだけ始められる（呼び出し側が確認する）。
    @discardableResult
    func beginWait(kind: WaitKind = .pause) -> Bool {
        reconcile()
        // 同じ種類の待機は、続きから。別の種類の待機が残っていたら、それは破棄して、新しく始める（進みは引き継がない）
        if let wait, wait.kind == kind { return true }
        let seconds = rules.waitSeconds(for: kind)
        var next = state ?? PauseState()
        next.wait = PauseWait(kind: kind, required: seconds, remaining: seconds, lastActiveAt: now(), readyAt: nil)
        save(next)
        countdown = nil
        return true
    }

    /// 待機をやめる。制限はそのまま続く。進んだ分は引き継がない。
    func cancelWait() {
        reconcile()
        guard var next = state else { return }
        next.wait = nil
        save(next)
        countdown = nil
    }

    func activate() {
        guard let wait, !wait.isReady else { return }
        if countdown == nil { countdown = WaitCountdown(remaining: wait.remaining) }
        countdown?.resume(at: clock.now())
    }

    func tick() {
        guard var c = countdown, c.isRunning, var next = state, var wait = next.wait, !wait.isReady else { return }
        c.tick(at: clock.now())
        countdown = c
        wait.remaining = c.remaining
        wait.lastActiveAt = now()
        if c.isFinished {
            wait.readyAt = now()
            next.wait = wait
            save(next)
            countdown = nil
            return
        }
        next.wait = wait
        // 毎回は保存しない（約5秒おき）。強制終了しても、保存済みの残りから再開する（飛ばせない）
        if clock.now() - lastSavedAt >= 5 {
            lastSavedAt = clock.now()
            store.state = next
        }
        state = next
    }

    /// 前面でなくなった・画面を離れたとき。残りを保存する（バックグラウンドでは進まない）。
    func deactivate() {
        guard var c = countdown, var next = state, var wait = next.wait, !wait.isReady else { return }
        c.pause(at: clock.now())
        countdown = c
        wait.remaining = c.remaining
        wait.lastActiveAt = now()
        if c.isFinished { wait.readyAt = now() }
        next.wait = wait
        save(next)
        if c.isFinished { countdown = nil }
    }

    /// 描画用の、いまの残り時間（毎フレーム呼んでよい）。
    func liveRemaining() -> TimeInterval {
        guard let wait else { return 0 }
        if wait.isReady { return 0 }
        return countdown?.remaining(at: clock.now()) ?? wait.remaining
    }

    func liveProgress() -> Double {
        guard let wait, wait.required > 0 else { return 1 }
        return min(1, max(0, 1 - liveRemaining() / wait.required))
    }

    // MARK: 停止

    /// 本人が「停止する」を押したとき。再制限の監視と状態の保存ができた場合だけ、制限を外す。
    /// 延長・再停止も、この手順（待機）を通る。30分は、いまこの瞬間から数える。
    func confirmPause() -> PauseStartResult {
        reconcile()
        guard isReady, wait?.kind == .pause else {
            if let wait, wait.isReady, wait.kind == .pause { var next = state ?? PauseState(); next.wait = nil; save(next) }
            return .notReady
        }
        let previous = state
        let oldWindow = previous?.window
        guard let itemsData = oldWindow?.itemsData ?? shield.currentItemsData() else { return .failed(.notRestricted) }

        let start = now()
        let end = start.addingTimeInterval(rules.pauseSeconds)
        let name = PauseState.activityPrefix + UUID().uuidString
        let window = PauseWindow(activityName: name, pausedAt: start, endsAt: end, itemsData: itemsData)

        // 先に状態を保存し、次に監視を登録し、最後に制限を外す。どこで失敗しても、制限は外れない。
        let pending = PauseState(wait: nil, window: window)
        store.state = pending
        do {
            try scheduler.startWindow(name: name, from: start, to: end)
        } catch {
            store.state = previous
            state = previous
            return .failed(.scheduling)
        }
        shield.endOrdinaryUnlock()
        guard shield.relaxAll() else {
            scheduler.stopWindows(keeping: oldWindow?.activityName)
            // 制限を外せなかった。元の制限へ戻して、失敗を返す
            shield.restore(itemsData: itemsData)
            store.state = previous
            state = previous
            return .failed(.shield)
        }
        scheduler.stopWindows(keeping: name)
        state = pending
        countdown = nil
        return .started(until: end)
    }

    /// 制限の終了：待機（長い）が終わっているときだけ true を返し、待機を消す。実際の終了は、呼び出し側が行う。
    func confirmEnd() -> Bool {
        reconcile()
        guard isReady, wait?.kind == .end else { return false }
        var next = state ?? PauseState()
        next.wait = nil
        save(next)
        return true
    }

    /// 停止を、いま終える（制限を強める操作なので、待機なしでいつでもできる）。
    func resumeRestrictionNow() {
        reconcile()
        guard let window else { return }
        shield.restore(itemsData: window.itemsData)
        scheduler.stopWindows(keeping: nil)
        var next = state ?? PauseState()
        next.window = nil
        save(next)
    }

    /// すべてを消す（恒久的な終了・開発用の解除のとき）。
    func clearAll() {
        scheduler.stopWindows(keeping: nil)
        store.state = nil
        state = nil
        countdown = nil
    }

    private func save(_ next: PauseState) {
        let value: PauseState? = next.isEmpty ? nil : next
        store.state = value
        state = value
    }
}
