import SwiftData
import XCTest
@testable import Futo

/// 待機0分・解除の残り時間・制限対象の追加まわり。Screen Time（実機）が必要な部分は、ここでは確かめない。
@MainActor
final class ControlImprovementTests: XCTestCase {
    private var container: ModelContainer!
    private var store: SessionStore!
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        container = try ModelContainer(for: Session.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = SessionStore(context: container.mainContext, now: { [base] in base })
        LanguageStore.shared.select(.ja)
    }

    override func tearDown() async throws { LanguageStore.shared.select(.ja) }

    // MARK: 待機0分

    func testZeroIsAnOptionAndExistingValuesAreKept() {
        XCTAssertEqual(Preferences.waitOptions.first, 0)
        XCTAssertEqual(Preferences.waitOptions.dropFirst(), [10, 30, 60, 300, 600])
        XCTAssertEqual(Preferences().effectiveWaitSeconds, Preferences.defaultWaitSeconds, "新規の初期値は、いままでどおり")
        var old = Preferences(); old.waitSeconds = 300
        XCTAssertEqual(old.effectiveWaitSeconds, 300, "既存の設定は、勝手に0にならない")
        var zero = Preferences(); zero.waitSeconds = 0
        XCTAssertEqual(zero.effectiveWaitSeconds, 0)
    }

    func testZeroWaitSkipsTheWaitingPhaseAndStillRequiresTheChoice() {
        let session = store.begin(mode: .device, requiredWaitSeconds: 0)
        XCTAssertTrue(store.startWaiting(session, purpose: .contact))
        XCTAssertEqual(session.phase, .awaitingChoice, "待機の画面は通らない")
        XCTAssertEqual(session.remainingWaitSeconds, 0)
        XCTAssertFalse(store.startWaiting(session, purpose: .research), "二重に押しても、何も起きない")
        XCTAssertEqual(session.purpose, .contact)
        XCTAssertTrue(store.finish(session, outcome: .wantsToUse))
        XCTAssertFalse(store.finish(session, outcome: .wantsToUse), "解除の開始は、1回だけ")
        XCTAssertEqual(session.phase, .completed)
    }

    func testNonZeroWaitStillWaits() {
        let session = store.begin(mode: .device, requiredWaitSeconds: 10)
        store.startWaiting(session, purpose: nil)
        XCTAssertEqual(session.phase, .waiting)
        XCTAssertEqual(session.remainingWaitSeconds, 10)
        XCTAssertFalse(store.finish(session, outcome: .wantsToUse), "待機が終わるまでは、選べない")
    }

    func testChangingWaitBetweenZeroAndOthers() {
        var prefs = Preferences()
        prefs.setWait(0, now: base)                      // 短くする（ゆるめる）ので、1分後に反映
        XCTAssertEqual(prefs.effectiveWaitSeconds(now: base), 60)
        XCTAssertEqual(prefs.effectiveWaitSeconds(now: base.addingTimeInterval(61)), 0)
        prefs.settlePending(now: base.addingTimeInterval(61))
        XCTAssertEqual(prefs.waitSeconds, 0)
        prefs.setWait(300, now: base.addingTimeInterval(62)) // 長くする（きびしくする）のは、すぐ
        XCTAssertEqual(prefs.effectiveWaitSeconds(now: base.addingTimeInterval(62)), 300)
    }

    func testWaitSessionKeepsItsOwnWaitWhenSettingChanges() {
        let session = store.begin(mode: .device, requiredWaitSeconds: 60)
        var prefs = Preferences(); prefs.setWait(0, now: base)
        XCTAssertEqual(session.requiredWaitSeconds, 60, "進行中のひと呼吸の待機は、設定を変えても変わらない")
        XCTAssertEqual(prefs.effectiveWaitSeconds(now: base.addingTimeInterval(120)), 0)
    }

    func testSuggestionsNeverProposeZeroWait() {
        var prefs = Preferences(); prefs.waitSeconds = 10
        let sessions = (0..<10).map { i -> Session in
            let s = Session(mode: .device, startedAt: base.addingTimeInterval(Double(-3600 * (i + 1))), requiredWaitSeconds: 10)
            s.phase = .interrupted; s.outcome = .interrupted
            return s
        }
        var state = SuggestionState()
        let suggestion = SuggestionEngine.evaluate(state: &state, sessions: sessions, mode: .device, preferences: prefs,
                                                   calendar: LogicalCalendar(), now: base)
        if case .waitSeconds(let value)? = suggestion?.change { XCTAssertGreaterThan(value, 0) }
        prefs.waitSeconds = 0
        var state2 = SuggestionState()
        let none = SuggestionEngine.evaluate(state: &state2, sessions: sessions, mode: .device, preferences: prefs,
                                             calendar: LogicalCalendar(), now: base)
        XCTAssertNotEqual(none?.kind, .waitShorter, "すでに0なら、これ以上短くする提案はない")
    }

    func testZeroWaitLabelInBothLanguages() {
        XCTAssertEqual(durationText(seconds: 0), "0分（待機なし）")
        LanguageStore.shared.select(.en)
        XCTAssertEqual(durationText(seconds: 0), "0 min (no wait)")
    }

    // MARK: 解除の残り時間

    func testRemainingTextUnits() {
        XCTAssertEqual(unlockRemainingText(12 * 60), "あと12分")
        XCTAssertEqual(unlockRemainingText(12 * 60 - 1), "あと12分", "切り上げ")
        XCTAssertEqual(unlockRemainingText(61), "あと2分")
        XCTAssertEqual(unlockRemainingText(60), "あと60秒")
        XCTAssertEqual(unlockRemainingText(30), "あと30秒")
        XCTAssertEqual(unlockRemainingText(0.4), "あと1秒")
        XCTAssertNil(unlockRemainingText(0), "終わったら出さない")
        XCTAssertNil(unlockRemainingText(-5))
        LanguageStore.shared.select(.en)
        XCTAssertEqual(unlockRemainingText(12 * 60), "12 min left")
        XCTAssertEqual(unlockRemainingText(30), "30s left")
    }

    func testUsableUntilUsesTheEarlierOfConfiguredMinutesAndWindowEnd() {
        let start = base
        // 5分の設定、監視区間は16分：5分
        var record = UnlockRecord(activityName: "a", startedAt: start, endsAt: start.addingTimeInterval(16 * 60),
                                  unlocked: nil, sessionID: nil, minutes: 5)
        XCTAssertEqual(record.usableUntil, start.addingTimeInterval(300))
        // 30分の設定、監視区間は31分：30分
        record.minutes = 30; record.endsAt = start.addingTimeInterval(31 * 60)
        XCTAssertEqual(record.usableUntil, start.addingTimeInterval(1800))
        // 古い記録（分数なし）は、区間の終わり
        record.minutes = nil
        XCTAssertEqual(record.usableUntil, record.endsAt)
        // 時刻から求めるので、アプリを閉じていても（時間が進んでも）正しい
        XCTAssertEqual(unlockRemainingText(record.usableUntil.timeIntervalSince(start.addingTimeInterval(20 * 60))), "あと11分")
    }
}
