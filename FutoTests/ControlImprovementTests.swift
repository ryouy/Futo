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

    // MARK: 一時解除（経過時間）

    func testEndIsStartPlusMinutesForEverySetting() {
        for minutes in [1, 5, 10, 15, 30, 60] {
            XCTAssertEqual(UnlockTiming.endsAt(start: base, minutes: minutes), base.addingTimeInterval(TimeInterval(minutes) * 60))
        }
    }

    func testPrimaryScheduleKeepsEndAndMeetsAppleMinimum() {
        for minutes in [1, 5, 10, 15, 30, 60] {
            let w = UnlockTiming.primarySchedule(start: base, minutes: minutes)
            XCTAssertEqual(w.end, base.addingTimeInterval(TimeInterval(minutes) * 60), "終わりは、解除の終わりに合わせる（\(minutes)分）")
            XCTAssertGreaterThanOrEqual(w.end.timeIntervalSince(w.start), UnlockTiming.minimumMonitorSeconds, "区間は15分以上（\(minutes)分）")
            XCTAssertLessThanOrEqual(w.start, base, "始まりは、今より未来にならない")
        }
        XCTAssertEqual(UnlockTiming.primarySchedule(start: base, minutes: 5).start, base.addingTimeInterval(-10 * 60), "5分は、始まりを10分前にずらす")
        XCTAssertEqual(UnlockTiming.primarySchedule(start: base, minutes: 30).start, base, "15分以上は、ずらさない")
    }

    func testFallbackScheduleIsNeverShorterThanFifteenMinutes() {
        XCTAssertEqual(UnlockTiming.fallbackSchedule(start: base, minutes: 5).end, base.addingTimeInterval(15 * 60), "代わりの区間は、短い解除では遅く終わる")
        XCTAssertEqual(UnlockTiming.fallbackSchedule(start: base, minutes: 30).end, base.addingTimeInterval(30 * 60))
    }

    func testRemainingTextUnits() {
        XCTAssertEqual(unlockRemainingText(12 * 60), "あと12分")
        XCTAssertEqual(unlockRemainingText(12 * 60 - 1), "あと12分", "切り上げ")
        XCTAssertEqual(unlockRemainingText(61), "あと2分")
        XCTAssertEqual(unlockRemainingText(60), "あと60秒")
        XCTAssertEqual(unlockRemainingText(45), "あと45秒")
        XCTAssertEqual(unlockRemainingText(0.4), "あと1秒")
        XCTAssertNil(unlockRemainingText(0), "終わったら出さない")
        XCTAssertNil(unlockRemainingText(-5))
        LanguageStore.shared.select(.en)
        XCTAssertEqual(unlockRemainingText(12 * 60), "12 min left")
        XCTAssertEqual(unlockRemainingText(45), "45s left")
    }

    func testRemainingDependsOnlyOnStoredEnd() {
        // 解除から5分。終了時刻は保存されたもの。途中の経過（アプリを閉じる・再起動・ロック）に関係なく、時刻だけで決まる
        let end = UnlockTiming.endsAt(start: base, minutes: 5)
        XCTAssertEqual(unlockRemainingText(end.timeIntervalSince(base.addingTimeInterval(60))), "あと4分")
        XCTAssertEqual(unlockRemainingText(end.timeIntervalSince(base.addingTimeInterval(255))), "あと45秒")
        XCTAssertNil(unlockRemainingText(end.timeIntervalSince(base.addingTimeInterval(300))))
    }

    func testRecordCodableKeepsEndAndOldRecordsStillDecode() throws {
        let record = UnlockRecord(activityName: "a", startedAt: base, endsAt: base.addingTimeInterval(300), unlocked: nil,
                                  sessionID: nil, minutes: 5, monitorEndsAt: base.addingTimeInterval(300))
        let back = try JSONDecoder().decode(UnlockRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(back, record, "再起動（保存と読み込み）で、終了時刻は変わらない")
        let old = #"{"activityName":"a","startedAt":0,"endsAt":960}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(UnlockRecord.self, from: old).monitorEndsAt)
    }

    func testAddFeedbackOnlyWhenSomethingWasActuallyAdded() {
        XCTAssertEqual(AppModel.addOutcome(added: 2, removedSelf: false), .added)
        XCTAssertEqual(AppModel.addOutcome(added: 0, removedSelf: false), .nothing, "何も選ばない・既存だけの重複選択では出さない")
        XCTAssertEqual(AppModel.addOutcome(added: 0, removedSelf: true), .ownApp)
        XCTAssertEqual(AppModel.addOutcome(added: 1, removedSelf: true), .ownApp, "ふと自身が混ざったときは、その案内を優先")
    }

    func testAddTextsInBothLanguages() {
        LanguageStore.shared.select(.ja)
        XCTAssertEqual(tr("制限する項目を追加"), "制限する項目を追加")
        LanguageStore.shared.select(.en)
        for key in ["制限する項目を追加", "制限する項目を追加しました", "追加したいアプリやWebサイトを選んでください", "現在の制限対象は、そのまま残ります",
                    "減らすには、制限を終了してください", "追加も、外すこともできます"] {
            XCTAssertNotEqual(tr(key), key, "英訳がある：\(key)")
        }
    }

    // MARK: 緩和の反映待ち

    func testFirstLoosenStartsSixtySecondCountdown() {
        var p = Preferences()
        XCTAssertNil(p.loosenRemaining(now: base))
        p.setWait(30, now: base)
        XCTAssertEqual(p.loosenRemaining(now: base), 60)
        XCTAssertEqual(p.loosenRemaining(now: base.addingTimeInterval(1)), 59, "1秒ごとに減る（時刻から求める）")
        XCTAssertEqual(p.loosenRemaining(now: base.addingTimeInterval(30)), 30)
        XCTAssertEqual(p.loosenRemaining(now: base.addingTimeInterval(55)), 5)
        XCTAssertNil(p.loosenRemaining(now: base.addingTimeInterval(60)), "反映されたら出さない")
        XCTAssertEqual(p.loosenAppliesAt, base.addingTimeInterval(60))
    }

    func testNewLoosenResetsTheTimerForEverythingPending() {
        var p = Preferences()
        p.setWait(60, now: base.addingTimeInterval(-1))   // 同じ値：緩めてはいない
        p.setUnlockMinutes(10, now: base)                  // 解除を長く（緩める）→ 60秒開始
        p.setWait(30, now: base.addingTimeInterval(30))    // 待機を短く（緩める）→ 全体が60秒に戻る
        XCTAssertEqual(p.loosenRemaining(now: base.addingTimeInterval(30)), 60)
        XCTAssertEqual(p.loosenAppliesAt, base.addingTimeInterval(90), "最後に緩めた時点から1分後")
        // 古い予定（最初の変更の60秒後）では、反映されない
        XCTAssertEqual(p.effectiveUnlockMinutes(now: base.addingTimeInterval(61)), Preferences.defaultUnlockMinutes)
        XCTAssertEqual(p.effectiveWaitSeconds(now: base.addingTimeInterval(61)), 60)
        // 最後から60秒後に、まとめて反映される
        let due = base.addingTimeInterval(91)
        XCTAssertEqual(p.effectiveUnlockMinutes(now: due), 10)
        XCTAssertEqual(p.effectiveWaitSeconds(now: due), 30)
        p.settlePending(now: due)
        XCTAssertEqual(p.waitSeconds, 30); XCTAssertEqual(p.unlockMinutes, 10)
        XCTAssertNil(p.loosenAppliesAt)
    }

    func testPendingValueAndEffectiveValueAreNotMixedUp() {
        var p = Preferences(); p.waitSeconds = 300
        p.setWait(0, now: base)
        XCTAssertEqual(p.effectiveWaitSeconds(now: base.addingTimeInterval(10)), 300, "反映までは、いまの値のまま")
        XCTAssertEqual(p.pendingWaitSeconds, 0)
        XCTAssertEqual(p.effectiveWaitSeconds(now: base.addingTimeInterval(60)), 0)
    }

    func testNoOpAndStrengtheningDoNotResetOrEarlyApply() {
        var p = Preferences()
        p.setUnlockMinutes(10, now: base)                    // 緩める：待ち開始
        p.setUnlockMinutes(10, now: base.addingTimeInterval(20)) // 同じ値の選び直し：リセットしない
        XCTAssertEqual(p.loosenRemaining(now: base.addingTimeInterval(20)), 40)
        p.setWait(600, now: base.addingTimeInterval(25))     // 強める：すぐ反映、待ちには触れない
        XCTAssertEqual(p.waitSeconds, 600)
        XCTAssertEqual(p.loosenRemaining(now: base.addingTimeInterval(25)), 35, "強める変更で、待っている変更の時計は動かない")
        XCTAssertEqual(p.effectiveUnlockMinutes(now: base.addingTimeInterval(59)), Preferences.defaultUnlockMinutes, "早期反映しない")
        XCTAssertEqual(p.effectiveUnlockMinutes(now: base.addingTimeInterval(60)), 10)
    }

    func testPendingSurvivesRestartAndBackground() throws {
        var p = Preferences()
        p.setWait(10, now: base)
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(restored, p)
        // 再起動（またはバックグラウンド）から40秒後に戻っても、残りは20秒
        XCTAssertEqual(restored.loosenRemaining(now: base.addingTimeInterval(40)), 20)
        XCTAssertEqual(restored.effectiveWaitSeconds(now: base.addingTimeInterval(61)), 10)
    }

    func testCountdownTextInBothLanguages() {
        LanguageStore.shared.select(.ja)
        XCTAssertEqual(tr("反映まで あと{0}秒", "30"), "反映まで あと30秒")
        LanguageStore.shared.select(.en)
        XCTAssertEqual(tr("反映まで あと{0}秒", "30"), "Takes effect in 30s")
    }

    // MARK: 起動・復帰で「制限しました」を出さない

    private let soon = Date(timeIntervalSince1970: 1_800_000_300)

    func testReconfirmingAnExistingLockShowsNothing() {
        // 起動・前面への復帰・Shieldの再適用：制限中のまま
        XCTAssertEqual(AppModel.sealChange(previous: .configured, current: .configured, userStartedLock: false).locked, false)
        XCTAssertEqual(AppModel.sealChange(previous: .configured, current: .configured, userStartedLock: false).unlocked, false)
        // 起動の直後など、一瞬「確認できない」「制限なし」から、制限中と分かっただけ
        XCTAssertFalse(AppModel.sealChange(previous: .unverifiable, current: .configured, userStartedLock: false).locked)
        XCTAssertFalse(AppModel.sealChange(previous: .off, current: .configured, userStartedLock: false).locked)
    }

    func testUserStartingALockShowsTheSeal() {
        XCTAssertTrue(AppModel.sealChange(previous: .off, current: .configured, userStartedLock: true).locked)
        XCTAssertTrue(AppModel.sealChange(previous: .unverifiable, current: .configured, userStartedLock: true).locked)
    }

    func testRealTransitionsStillShowTheSeal() {
        // 一時解除・一時停止が終わって、制限に戻った
        XCTAssertTrue(AppModel.sealChange(previous: .temporarilyUnlocked(until: soon), current: .configured, userStartedLock: false).locked)
        XCTAssertTrue(AppModel.sealChange(previous: .paused(until: soon), current: .configured, userStartedLock: false).locked)
        // 制限中から、解除・停止・終了
        XCTAssertTrue(AppModel.sealChange(previous: .configured, current: .temporarilyUnlocked(until: soon), userStartedLock: false).unlocked)
        XCTAssertTrue(AppModel.sealChange(previous: .configured, current: .paused(until: soon), userStartedLock: false).unlocked)
        XCTAssertTrue(AppModel.sealChange(previous: .configured, current: .off, userStartedLock: false).unlocked)
        XCTAssertFalse(AppModel.sealChange(previous: .configured, current: .unverifiable, userStartedLock: false).unlocked, "確認できないだけでは、「解除しました」も出さない")
    }

    func testSealWordingInBothLanguages() {
        LanguageStore.shared.select(.ja)
        XCTAssertEqual(tr("制限しました"), "制限しました")
        LanguageStore.shared.select(.en)
        XCTAssertNotEqual(tr("制限しました"), "制限しました")
    }
}
