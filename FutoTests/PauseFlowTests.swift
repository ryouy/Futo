import XCTest
@testable import Futo

// MARK: 偽物（OSの代わり）

final class FakePauseStore: PauseStoring {
    var state: PauseState? { didSet { log.append("store"); onWrite?() } }
    var log: [String] = []
    var onWrite: (() -> Void)?
}

final class FakeScheduler: PauseScheduling {
    var monitoring: Set<String> = []
    var shouldFail = false
    var log: [String] = []
    var onCall: ((String) -> Void)?
    var windows: [(name: String, from: Date, to: Date)] = []

    func isMonitoring(_ name: String) -> Bool { monitoring.contains(name) }
    func startWindow(name: String, from start: Date, to end: Date) throws {
        log.append("schedule"); onCall?("schedule")
        if shouldFail { throw URLError(.unknown) }
        monitoring.insert(name)
        windows.append((name, start, end))
    }
    func stopWindows(keeping keep: String?) {
        log.append("stop")
        monitoring = monitoring.filter { $0 == keep }
    }
}

final class FakeShield: PauseShielding {
    var items: Data? = Data("ITEMS".utf8)
    var relaxed = false
    var canRelax = true
    var ordinaryUnlockEnded = 0
    var restored: [Data] = []
    var log: [String] = []

    func currentItemsData() -> Data? { relaxed ? nil : items }
    func endOrdinaryUnlock() { ordinaryUnlockEnded += 1; log.append("endUnlock") }
    var onCall: ((String) -> Void)?
    func relaxAll() -> Bool { log.append("relax"); onCall?("relax"); if canRelax { relaxed = true }; return canRelax }
    func restore(itemsData: Data) { restored.append(itemsData); relaxed = false; log.append("restore") }
}

final class TestClock: MonotonicClock {
    var uptime: TimeInterval = 1_000
    func now() -> TimeInterval { uptime }
}

@MainActor
final class PauseFlowTests: XCTestCase {
    private let rules = PauseRules(waitSeconds: 600, pauseMinutes: 30)
    private var store: FakePauseStore!
    private var scheduler: FakeScheduler!
    private var shield: FakeShield!
    private var clock: TestClock!
    private var wall = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        store = FakePauseStore(); scheduler = FakeScheduler(); shield = FakeShield(); clock = TestClock()
        wall = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private func makeFlow() -> PauseFlow {
        PauseFlow(store: store, scheduler: scheduler, shield: shield, rules: rules, now: { [unowned self] in self.wall }, clock: clock)
    }

    /// 前面で `seconds` 秒すごす（時計を進めて、ティックする）。
    private func spend(_ seconds: TimeInterval, in flow: PauseFlow) {
        clock.uptime += seconds; wall.addTimeInterval(seconds)
        flow.tick()
    }

    private func finishWait(_ flow: PauseFlow) {
        flow.beginWait(); flow.activate()
        spend(600, in: flow)
    }

    func testBeginningTheWaitDoesNotTouchTheRestriction() {
        let flow = makeFlow()
        flow.beginWait()
        XCTAssertTrue(flow.isWaiting)
        XCTAssertFalse(shield.relaxed)
        XCTAssertTrue(scheduler.log.isEmpty, "待機の開始では、何も登録しない")
        XCTAssertEqual(shield.log, [])
        XCTAssertFalse(flow.isPaused)
    }

    func testWaitOnlyAdvancesWhileInForeground() {
        let flow = makeFlow()
        flow.beginWait(); flow.activate()
        spend(100, in: flow)
        XCTAssertEqual(flow.liveRemaining(), 500, accuracy: 0.01)
        flow.deactivate()                         // バックグラウンド・ロック
        clock.uptime += 3_000; wall.addTimeInterval(3_000)   // その間は、進まない
        XCTAssertEqual(flow.liveRemaining(), 500, accuracy: 0.01)
        flow.activate()
        spend(50, in: flow)
        XCTAssertEqual(flow.liveRemaining(), 450, accuracy: 0.01)
    }

    func testRelaunchKeepsProgressAndCannotSkipOrReset() {
        let first = makeFlow()
        first.beginWait(); first.activate()
        spend(120, in: first)
        first.deactivate()
        // アプリの強制終了→再起動：同じ保存から、続きから始まる（飛ばせない）
        let second = makeFlow()
        second.reconcile()
        XCTAssertEqual(second.liveRemaining(), 480, accuracy: 0.01)
        XCTAssertFalse(second.isReady)
        XCTAssertEqual(second.confirmPause(), .notReady)
        XCTAssertFalse(shield.relaxed)
    }

    func testClockMovingForwardWhileInactiveDoesNotShortenTheWait() {
        let flow = makeFlow()
        flow.beginWait(); flow.activate()
        spend(10, in: flow)
        flow.deactivate()
        wall.addTimeInterval(3_500)               // 時刻を進めても（アイドルの上限内）、残りは減らない
        flow.reconcile()
        XCTAssertEqual(flow.liveRemaining(), 590, accuracy: 0.01)
    }

    func testPauseCannotStartBeforeTheWaitFinishes() {
        let flow = makeFlow()
        flow.beginWait(); flow.activate()
        spend(599, in: flow)
        XCTAssertFalse(flow.isReady)
        XCTAssertEqual(flow.confirmPause(), .notReady)
        XCTAssertFalse(shield.relaxed)
        XCTAssertFalse(flow.isPaused)
    }

    func testFinishingTheWaitDoesNotUnlockByItself() {
        let flow = makeFlow()
        finishWait(flow)
        XCTAssertTrue(flow.isReady)
        XCTAssertFalse(shield.relaxed, "待機が終わっても、自動では解除しない")
        XCTAssertFalse(flow.isPaused)
    }

    func testThirtyMinutesCountFromTheMomentOfActualRelease() {
        let flow = makeFlow()
        finishWait(flow)
        wall.addTimeInterval(240)                  // 待機が終わってから4分後に、本人が押す
        let pressedAt = wall
        guard case .started(let until) = flow.confirmPause() else { return XCTFail() }
        XCTAssertEqual(until.timeIntervalSince(pressedAt), 30 * 60, accuracy: 0.001)
        XCTAssertEqual(flow.window?.pausedAt, pressedAt)
        XCTAssertTrue(shield.relaxed)
        XCTAssertEqual(shield.ordinaryUnlockEnded, 1, "進行中の通常の一時解除より、停止が優先される")
        XCTAssertEqual(flow.window?.itemsData, Data("ITEMS".utf8), "停止前の対象を保存する")
        XCTAssertNil(flow.wait)
    }

    func testStateIsSavedAndMonitoringRegisteredBeforeTheRestrictionIsLifted() {
        let flow = makeFlow()
        finishWait(flow)
        var order: [String] = []
        let store = self.store!, scheduler = self.scheduler!, shield = self.shield!
        // 呼び出し順を記録する
        let probe = OrderProbe(store: store, scheduler: scheduler, shield: shield)
        _ = flow.confirmPause()
        order = probe.order
        let scheduleIndex = order.firstIndex(of: "schedule") ?? Int.max
        let relaxIndex = order.firstIndex(of: "relax") ?? Int.max
        XCTAssertLessThan(scheduleIndex, relaxIndex, "監視の登録が先、制限を外すのは最後")
        XCTAssertNotNil(self.store.state?.window)
    }

    func testIfMonitoringCannotBeRegisteredTheRestrictionStaysAndNothingIsPaused() {
        let flow = makeFlow()
        finishWait(flow)
        scheduler.shouldFail = true
        XCTAssertEqual(flow.confirmPause(), .failed(.scheduling))
        XCTAssertFalse(shield.relaxed, "再制限を保証できないときは、制限を外さない")
        XCTAssertFalse(flow.isPaused)
        XCTAssertNil(store.state?.window)
        XCTAssertTrue(flow.isReady, "待機は残るので、すぐ再試行できる")
        scheduler.shouldFail = false
        guard case .started = flow.confirmPause() else { return XCTFail("再試行で成功する") }
    }

    func testIfTheRestrictionCannotBeLiftedItIsRestoredAndFailureIsReported() {
        let flow = makeFlow()
        finishWait(flow)
        shield.canRelax = false
        XCTAssertEqual(flow.confirmPause(), .failed(.shield))
        XCTAssertFalse(flow.isPaused)
        XCTAssertNil(store.state?.window)
        XCTAssertTrue(scheduler.monitoring.isEmpty, "登録した監視も、取り消す")
    }

    func testNothingToRestoreMeansNoPause() {
        let flow = makeFlow()
        shield.items = nil
        finishWait(flow)
        XCTAssertEqual(flow.confirmPause(), .failed(.notRestricted))
    }

    func testExtensionNeedsANewWaitAndReplacesTheWindowKeepingTheOriginalItems() {
        let flow = makeFlow()
        finishWait(flow)
        guard case .started = flow.confirmPause() else { return XCTFail() }
        let first = flow.window!
        XCTAssertEqual(flow.confirmPause(), .notReady, "待機なしの再停止・延長はできない")

        // 停止中にもう一度待機する（制限は、まだ解除されたまま）
        wall.addTimeInterval(300)
        finishWait(flow)
        XCTAssertTrue(flow.isPaused)
        guard case .started(let until) = flow.confirmPause() else { return XCTFail() }
        let second = flow.window!
        XCTAssertNotEqual(first.activityName, second.activityName)
        XCTAssertEqual(second.itemsData, first.itemsData, "元の制限対象を引き継ぐ（解除中の空の状態を保存しない）")
        XCTAssertEqual(until.timeIntervalSince(wall), 30 * 60, accuracy: 0.001)
        XCTAssertEqual(scheduler.monitoring, [second.activityName], "古い区間の監視は止める")
    }

    func testOldWindowEventsCannotOverwriteTheNewState() {
        let flow = makeFlow()
        finishWait(flow)
        _ = flow.confirmPause()
        let first = flow.window!
        wall.addTimeInterval(60)
        finishWait(flow)
        _ = flow.confirmPause()
        XCTAssertFalse(flow.state!.isCurrentWindow(first.activityName), "古い区間の名前は、もう現在のものではない")
        XCTAssertTrue(flow.state!.isCurrentWindow(flow.window!.activityName))
    }

    func testReconcileRestoresWhenTheWindowHasEndedOrMonitoringIsGone() {
        let flow = makeFlow()
        finishWait(flow)
        _ = flow.confirmPause()
        // 拡張が動かなかった場合：期限を過ぎていたら、アプリが前面に戻ったときに再制限する
        wall.addTimeInterval(30 * 60 + 1)
        flow.reconcile()
        XCTAssertFalse(flow.isPaused)
        XCTAssertEqual(shield.restored, [Data("ITEMS".utf8)])
        XCTAssertFalse(shield.relaxed)
    }

    func testReconcileRestoresImmediatelyIfTheOSDroppedTheMonitoring() {
        let flow = makeFlow()
        finishWait(flow)
        _ = flow.confirmPause()
        scheduler.monitoring = []                  // OSが監視を落とした：再制限を保証できない
        flow.reconcile()
        XCTAssertFalse(flow.isPaused)
        XCTAssertEqual(shield.restored.count, 1)
    }

    func testReconcileLeavesAnActiveWindowAlone() {
        let flow = makeFlow()
        finishWait(flow)
        _ = flow.confirmPause()
        wall.addTimeInterval(10 * 60)
        flow.reconcile()
        XCTAssertTrue(flow.isPaused)
        XCTAssertTrue(shield.restored.isEmpty)
    }

    func testRelaunchWhilePausedKeepsThePauseAndItsEnd() {
        let flow = makeFlow()
        finishWait(flow)
        guard case .started(let until) = flow.confirmPause() else { return XCTFail() }
        let relaunched = makeFlow()
        relaunched.reconcile()
        XCTAssertEqual(relaunched.window?.endsAt, until)
        XCTAssertTrue(relaunched.isPaused)
    }

    func testReadyStateExpiresAndTheWaitMustBeRepeated() {
        let flow = makeFlow()
        finishWait(flow)
        wall.addTimeInterval(601)                  // 押せる期間（10分）を過ぎた
        XCTAssertFalse(flow.isReady)
        XCTAssertEqual(flow.confirmPause(), .notReady)
        XCTAssertFalse(shield.relaxed)
        flow.reconcile()
        XCTAssertNil(flow.wait)
    }

    func testAbandonedWaitIsResetAfterTheIdleLimit() {
        let flow = makeFlow()
        flow.beginWait(); flow.activate()
        spend(30, in: flow)
        flow.deactivate()
        wall.addTimeInterval(3_601)
        flow.reconcile()
        XCTAssertNil(flow.wait, "長く放置した待機は、やり直し")
    }

    func testCancelingTheWaitKeepsTheRestrictionAndDropsTheProgress() {
        let flow = makeFlow()
        flow.beginWait(); flow.activate()
        spend(200, in: flow)
        flow.cancelWait()
        XCTAssertNil(flow.wait)
        XCTAssertFalse(shield.relaxed)
        XCTAssertTrue(scheduler.windows.isEmpty)
        flow.beginWait()
        XCTAssertEqual(flow.liveRemaining(), 600, accuracy: 0.01, "キャンセルで進みを貯められない")
    }

    func testResumeNowRestoresTheRestrictionWithoutAnyWait() {
        let flow = makeFlow()
        finishWait(flow)
        _ = flow.confirmPause()
        flow.resumeRestrictionNow()
        XCTAssertFalse(flow.isPaused)
        XCTAssertEqual(shield.restored.count, 1)
        XCTAssertTrue(scheduler.monitoring.isEmpty)
    }

    func testClearAllRemovesEverything() {
        let flow = makeFlow()
        finishWait(flow)
        _ = flow.confirmPause()
        flow.clearAll()
        XCTAssertNil(store.state)
        XCTAssertTrue(scheduler.monitoring.isEmpty)
    }

    // MARK: 制限の終了（長い待機）

    func testEndingTheRestrictionNeedsTheLongWaitAndTouchesNothingUntilThen() {
        let flow = makeFlow()
        flow.beginWait(kind: .end); flow.activate()
        XCTAssertEqual(flow.liveRemaining(), 1_800, accuracy: 0.01, "終了の待機は30分")
        spend(1_799, in: flow)
        XCTAssertFalse(flow.isReady)
        XCTAssertFalse(flow.confirmEnd())
        XCTAssertFalse(shield.relaxed)
        XCTAssertTrue(scheduler.log.isEmpty)
        spend(1, in: flow)
        XCTAssertTrue(flow.isReady)
        XCTAssertFalse(shield.relaxed, "待機が終わっても、自動では終了しない")
        XCTAssertTrue(flow.confirmEnd())
        XCTAssertNil(flow.wait)
        XCTAssertFalse(flow.confirmEnd(), "2回目は何も起きない")
    }

    func testAPauseWaitCannotEndTheRestrictionAndAnEndWaitCannotPause() {
        let flow = makeFlow()
        finishWait(flow)                           // 一時停止の待機（10分のテスト設定）
        XCTAssertFalse(flow.confirmEnd(), "一時停止の待機では、終了できない")
        flow.cancelWait()

        flow.beginWait(kind: .end); flow.activate()
        spend(1_800, in: flow)
        XCTAssertEqual(flow.confirmPause(), .notReady, "終了の待機では、停止できない")
        XCTAssertFalse(shield.relaxed)
    }

    func testStartingTheOtherKindDropsTheOldProgress() {
        let flow = makeFlow()
        flow.beginWait(kind: .pause); flow.activate()
        spend(300, in: flow)
        flow.beginWait(kind: .end)
        XCTAssertEqual(flow.waitKind, .end)
        XCTAssertEqual(flow.liveRemaining(), 1_800, accuracy: 0.01, "別の待機に、進みを引き継げない")
    }

    func testEndWaitAlsoExpiresIfNotPressedInTime() {
        let flow = makeFlow()
        flow.beginWait(kind: .end); flow.activate()
        spend(1_800, in: flow)
        wall.addTimeInterval(601)
        XCTAssertFalse(flow.confirmEnd())
    }

    func testRelaunchKeepsTheEndWaitProgress() {
        let first = makeFlow()
        first.beginWait(kind: .end); first.activate()
        spend(900, in: first)
        first.deactivate()
        let second = makeFlow()
        second.reconcile()
        XCTAssertEqual(second.waitKind, .end)
        XCTAssertEqual(second.liveRemaining(), 900, accuracy: 0.01)
    }

    func testWaitsSavedByAnOlderVersionAreReadAsPauseWaits() throws {
        let old = #"{"required":600,"remaining":120,"lastActiveAt":790000000}"#
        let wait = try JSONDecoder().decode(PauseWait.self, from: Data(old.utf8))
        XCTAssertEqual(wait.kind, .pause)
        XCTAssertEqual(wait.remaining, 120)
    }

    func testStandardRulesMatchTheSpec() {
        #if !DEBUG
        XCTAssertEqual(PauseRules.standard.waitSeconds, 60)
        XCTAssertEqual(PauseRules.standard.endWaitSeconds, 1_800)
        #endif
        XCTAssertEqual(PauseRules.standard.pauseMinutes, 30)
    }
}

/// 保存・登録・解除の呼び出し順を、1つの記録にまとめる。
final class OrderProbe {
    var order: [String] = []
    init(store: FakePauseStore, scheduler: FakeScheduler, shield: FakeShield) {
        // 各偽物のログを、順番を保ったまま集めるため、書き込みのたびに共有ログへ写す。
        store.onWrite = { [weak self] in self?.order.append("store") }
        scheduler.onCall = { [weak self] in self?.order.append($0) }
        shield.onCall = { [weak self] in self?.order.append($0) }
    }
}
