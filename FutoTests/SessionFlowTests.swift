import SwiftData
import XCTest
@testable import Futo

final class FakeClock: MonotonicClock {
    var value: TimeInterval = 1_000
    func now() -> TimeInterval { value }
}

@MainActor
final class SessionFlowTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SessionStore!
    private var clock: FakeClock!
    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try ModelContainer(
            for: Session.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        store = SessionStore(context: container.mainContext, now: { [unowned self] in self.now })
        clock = FakeClock()
    }

    private func waitingSession(mode: AppMode = .demo, seconds: Double = 180) -> Session {
        let session = store.begin(mode: mode, requiredWaitSeconds: seconds)
        store.startWaiting(session, purpose: .contact)
        return session
    }

    // MARK: 待機時間

    func testCountdownOnlyAdvancesWhileRunning() {
        var countdown = WaitCountdown(remaining: 100)
        countdown.tick(at: 10)                    // 開始前：減らない
        XCTAssertEqual(countdown.remaining, 100)
        countdown.resume(at: 10)
        countdown.pause(at: 40)
        XCTAssertEqual(countdown.remaining, 70)
        countdown.tick(at: 500)                   // 停止中：減らない
        XCTAssertEqual(countdown.remaining, 70)
        countdown.resume(at: 500)
        countdown.tick(at: 520)
        XCTAssertEqual(countdown.remaining, 50)
    }

    func testLiveRemainingIsReadOnlyAndFollowsClock() {
        var countdown = WaitCountdown(remaining: 10)
        XCTAssertEqual(countdown.remaining(at: 500), 10)    // 開始前は減らない
        countdown.resume(at: 100)
        XCTAssertEqual(countdown.remaining(at: 103.5), 6.5) // 描画用の問い合わせ
        XCTAssertEqual(countdown.remaining, 10)             // 状態は変わらない
        XCTAssertEqual(countdown.remaining(at: 999), 0)
    }

    func testCountdownNeverGoesNegativeAndIgnoresBackwardsClock() {
        var countdown = WaitCountdown(remaining: 5)
        countdown.resume(at: 100)
        countdown.tick(at: 90)                    // 時計が戻っても増減しない
        XCTAssertEqual(countdown.remaining, 5)
        countdown.tick(at: 1_000)
        XCTAssertEqual(countdown.remaining, 0)
        XCTAssertTrue(countdown.isFinished)
    }

    func testControllerRunsOnlyWhileActiveAndResumesFromSavedRemaining() {
        let session = waitingSession()
        var controller = WaitController(session: session, store: store, clock: clock)
        controller.activate()
        clock.value += 30
        controller.tick()
        controller.deactivate()                    // 非アクティブ化
        XCTAssertEqual(session.remainingWaitSeconds, 150)

        clock.value += 600                         // 非アクティブ中の時間は無視
        controller = WaitController(session: session, store: store, clock: clock)
        XCTAssertEqual(controller.remaining, 150)
        controller.activate()
        clock.value += 10
        controller.tick()
        XCTAssertEqual(controller.remaining, 140)
    }

    func testWaitCompletesOnceAndMovesToAwaitingChoice() {
        let session = waitingSession(seconds: 5)
        let controller = WaitController(session: session, store: store, clock: clock)
        controller.activate()
        clock.value += 6
        controller.tick()
        controller.tick()
        controller.deactivate()
        XCTAssertEqual(session.phase, .awaitingChoice)
        XCTAssertEqual(session.remainingWaitSeconds, 0)
    }

    func testSkippedAndAnsweredPurposeGetSameWait() {
        let a = store.begin(mode: .demo, requiredWaitSeconds: 180)
        store.startWaiting(a, purpose: nil)
        store.interrupt(a)
        let b = store.begin(mode: .demo, requiredWaitSeconds: 180)
        store.startWaiting(b, purpose: .research)
        XCTAssertEqual(a.remainingWaitSeconds, b.remainingWaitSeconds)
        XCTAssertNil(a.purpose)
        XCTAssertEqual(b.purpose, .research)
    }

    // MARK: 遷移

    func testCannotChooseBeforeWaitFinishes() {
        let session = waitingSession()
        XCTAssertFalse(store.finish(session, outcome: .deferred))
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertNil(session.outcome)
    }

    func testResumeDoesNotCreateNewSession() {
        let first = store.begin(mode: .demo, requiredWaitSeconds: 180)
        let again = store.begin(mode: .demo, requiredWaitSeconds: 180)
        XCTAssertEqual(first.id, again.id)
        XCTAssertEqual(store.all().count, 1)
    }

    func testFinishTwiceKeepsFirstOutcomeOnly() {
        let session = waitingSession(seconds: 1)
        XCTAssertTrue(store.markWaitFinished(session))
        XCTAssertTrue(store.finish(session, outcome: .wantsToUse))
        XCTAssertFalse(store.finish(session, outcome: .deferred))
        XCTAssertEqual(session.outcome, .wantsToUse)
        XCTAssertEqual(store.all().count, 1)
    }

    func testStartWaitingTwiceDoesNotResetRemaining() {
        let session = waitingSession()
        store.saveRemaining(session, seconds: 40)
        XCTAssertFalse(store.startWaiting(session, purpose: .change))
        XCTAssertEqual(session.remainingWaitSeconds, 40)
        XCTAssertEqual(session.purpose, .contact)
    }

    func testDiscardOnlyUnstartedSession() {
        let fresh = store.begin(mode: .demo, requiredWaitSeconds: 180)
        XCTAssertTrue(store.discardUnstarted(fresh))
        XCTAssertTrue(store.all().isEmpty)
        let started = waitingSession()
        XCTAssertFalse(store.discardUnstarted(started))
    }

    // MARK: 保存・集計・削除

    func testStateSurvivesNewContext() throws {
        let session = waitingSession()
        store.saveRemaining(session, seconds: 77)
        let reopened = SessionStore(context: ModelContext(container))
        let restored = try XCTUnwrap(reopened.openSession(mode: .demo))
        XCTAssertEqual(restored.id, session.id)
        XCTAssertEqual(restored.remainingWaitSeconds, 77)
        XCTAssertEqual(restored.phase, .waiting)
    }

    func testDailyCountsUseLocalCalendarAndSeparateModes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 2027-01-15 23:30 JST と 翌日 00:30 JST（UTCでは同じ日）
        let late = ISO8601DateFormatter().date(from: "2027-01-15T14:30:00Z")!
        let early = ISO8601DateFormatter().date(from: "2027-01-15T15:30:00Z")!

        func complete(_ mode: AppMode, _ outcome: SessionOutcome, at date: Date) {
            now = date
            let s = store.begin(mode: mode, requiredWaitSeconds: 1)
            store.startWaiting(s, purpose: nil)
            store.markWaitFinished(s)
            store.finish(s, outcome: outcome)
        }
        complete(.demo, .deferred, at: late)
        complete(.demo, .wantsToUse, at: early)
        complete(.device, .deferred, at: early)

        let all = store.all()
        let day1 = DailyCounts.today(sessions: all, mode: .demo, calendar: calendar, now: late)
        let day2 = DailyCounts.today(sessions: all, mode: .demo, calendar: calendar, now: early)
        let device = DailyCounts.today(sessions: all, mode: .device, calendar: calendar, now: early)
        XCTAssertEqual(day1, .init(deferred: 1, wantsToUse: 0))
        XCTAssertEqual(day2, .init(deferred: 0, wantsToUse: 1))
        XCTAssertEqual(device, .init(deferred: 1, wantsToUse: 0))
    }

    func testInterruptedIsNotCountedAsDeferredOrWants() {
        let session = waitingSession()
        store.interrupt(session)
        XCTAssertEqual(DailyCounts.today(sessions: store.all(), mode: .demo, now: now), .init())
    }

    func testDeleteAllClosesOpenSessionsThenRemovesEverything() {
        let open = waitingSession()
        let done = store.begin(mode: .device, requiredWaitSeconds: 1)
        store.startWaiting(done, purpose: nil)
        store.markWaitFinished(done)
        store.finish(done, outcome: .deferred)
        store.deleteAll()
        XCTAssertTrue(store.all().isEmpty)
        XCTAssertNil(store.openSession(mode: .demo))
        _ = open
    }

    func testTemporaryUnlockIsRecordedOnlyForWantsToUse() {
        let deferred = waitingSession()
        store.markWaitFinished(deferred)
        store.finish(deferred, outcome: .deferred)
        store.recordTemporaryUnlock(deferred)
        XCTAssertNil(deferred.temporaryUnlockStartedAt)

        let wants = store.begin(mode: .device, requiredWaitSeconds: 1)
        store.startWaiting(wants, purpose: nil)
        store.recordTemporaryUnlock(wants)               // 完了前は記録しない
        XCTAssertNil(wants.temporaryUnlockStartedAt)
        store.markWaitFinished(wants)
        store.finish(wants, outcome: .wantsToUse)
        store.recordTemporaryUnlock(wants)
        XCTAssertNotNil(wants.temporaryUnlockStartedAt)
    }

    func testReflectionOnlyAfterUnlockAndOnlyOnce() {
        let plain = waitingSession()
        store.markWaitFinished(plain)
        store.finish(plain, outcome: .wantsToUse)
        XCTAssertFalse(store.recordReflection(plain, .satisfied))   // 一時解除していない

        store.recordTemporaryUnlock(plain)
        XCTAssertTrue(store.recordReflection(plain, .neutral))
        XCTAssertFalse(store.recordReflection(plain, .wishedLess))  // 2回目は無視
        XCTAssertEqual(plain.reflection, .neutral)
    }
}
