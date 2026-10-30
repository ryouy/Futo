import SwiftData
import XCTest
@testable import Futo

@MainActor
final class Phase3Tests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var cal: LogicalCalendar!

    override func setUp() async throws {
        container = try ModelContainer(
            for: Session.self, ReflectionCard.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 2   // 月曜始まり
        cal = LogicalCalendar(calendar: calendar)
    }

    private func jst(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal.calendar
        f.timeZone = cal.calendar.timeZone
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    @discardableResult
    private func record(_ at: String, mode: AppMode = .demo, purpose: Purpose? = nil,
                        outcome: SessionOutcome? = .deferred, reflection: Reflection? = nil,
                        unlocked: Bool = false) -> Session {
        let s = Session(mode: mode, startedAt: jst(at), requiredWaitSeconds: 180)
        s.purpose = purpose
        s.outcome = outcome
        s.phase = outcome == .interrupted ? .interrupted : .completed
        s.reflection = reflection
        if unlocked { s.temporaryUnlockStartedAt = jst(at) }
        context.insert(s)
        return s
    }

    private func sessions() -> [Session] { (try? context.fetch(FetchDescriptor<Session>())) ?? [] }

    // MARK: 論理日（深夜の帰属）

    func testMidnightBelongsToPreviousDay() {
        XCTAssertEqual(cal.dayKey(for: jst("2027-01-14 01:30")), "2027-01-13")
        XCTAssertEqual(cal.dayKey(for: jst("2027-01-14 03:59")), "2027-01-13")
        XCTAssertEqual(cal.dayKey(for: jst("2027-01-14 04:00")), "2027-01-14")
    }

    func testWeekBoundaryUsesLogicalDay() {
        let week = cal.weekInterval(containing: jst("2027-01-13 12:00"))
        XCTAssertEqual(week.start, jst("2027-01-11 04:00"))
        XCTAssertEqual(week.end, jst("2027-01-18 04:00"))
        // 月曜の午前2時は、前の週（日曜の夜）に数える
        XCTAssertEqual(cal.weekInterval(containing: jst("2027-01-11 02:00")).start, jst("2027-01-04 04:00"))
    }

    // MARK: 朝夜の振り返り

    func testReflectionWindowAndMidnight() {
        let night = 21 * 60
        XCTAssertFalse(ReflectionSchedule.isAvailable(clockMinute: night, now: jst("2027-01-13 20:59"), calendar: cal))
        XCTAssertTrue(ReflectionSchedule.isAvailable(clockMinute: night, now: jst("2027-01-13 21:00"), calendar: cal))
        XCTAssertTrue(ReflectionSchedule.isAvailable(clockMinute: night, now: jst("2027-01-14 02:00"), calendar: cal))
        XCTAssertFalse(ReflectionSchedule.isAvailable(clockMinute: night, now: jst("2027-01-14 03:30"), calendar: cal))
        // 深夜0〜4時は前日の論理日なので、同じ夜のカードと同じキーになる
        XCTAssertEqual(cal.dayKey(for: jst("2027-01-13 22:00")), cal.dayKey(for: jst("2027-01-14 02:00")))
    }

    private func build(_ kind: ReflectionKind, _ seed: String = "2027-01-13") -> ReflectionContent {
        let range = ReflectionSchedule.contentRange(kind: kind, now: jst("2027-01-13 21:30"), calendar: cal,
                                                    useTodayForMorning: kind == .morning)
        return ReflectionBuilder.build(kind: kind, sessions: sessions(), mode: .demo, interval: range.interval,
                                       dayWord: range.dayWord, seed: seed)
    }

    func testBuilderNeutralWhenNoRecords() {
        let c = build(.night)
        XCTAssertEqual(c.lines.first, "今日は、記録がまだありません。")
        XCTAssertEqual(c.lines.count, 2, "記録が無くても、短い締めの一文だけ")
    }

    func testBuilderIsAbstractAndNeverListsNumbers() {
        for i in 0..<8 { record("2027-01-13 1\(i % 6):00", purpose: i < 6 ? .contact : .research,
                                  outcome: i % 3 == 0 ? .wantsToUse : .deferred, reflection: i == 0 ? .satisfied : nil,
                                  unlocked: i == 0) }
        for kind in ReflectionKind.allCases {
            let text = build(kind).lines.joined()
            let hasDigit = text.unicodeScalars.contains { ("0"..."9").contains($0) || ("０"..."９").contains($0) }
            XCTAssertFalse(hasDigit, "算用数字を並べない: \(text)")
        }
    }

    func testVolumeChangesTheOpening() {
        record("2027-01-13 10:00", purpose: .contact, outcome: .deferred)
        let few = build(.night).lines[0]
        for i in 0..<7 { record("2027-01-13 1\(i):00", purpose: .contact, outcome: .deferred) }
        let many = build(.night).lines[0]
        XCTAssertNotEqual(few, many)
        XCTAssertTrue(many.contains("多め") || many.contains("たくさん"))
    }

    func testMorningAndNightUseDifferentWording() {
        for i in 0..<4 { record("2027-01-13 1\(i):00", purpose: .contact, outcome: .deferred) }
        let morning = build(.morning).lines.last!
        let night = build(.night).lines.last!
        XCTAssertNotEqual(morning, night)
        XCTAssertTrue(["新しい一日のはじまりです。", "今日のペースで、ゆっくり。", "ゆっくり始めましょう。"].contains(morning))
        XCTAssertTrue(["今日はここまでです。", "一日の終わりです。", "ここでひと区切りにしましょう。"].contains(night))
    }

    func testBuilderBranchesOnDominantOutcomePurposeAndReflection() {
        for i in 0..<4 { record("2027-01-13 1\(i):00", purpose: .contact, outcome: .deferred) }
        record("2027-01-13 16:00", purpose: .contact, outcome: .wantsToUse, reflection: .wishedLess, unlocked: true)
        let text = build(.night).lines.joined(separator: "\n")
        XCTAssertTrue(text.contains("「やめておく」"), text)
        XCTAssertTrue(text.contains("「連絡」"), text)
        XCTAssertTrue(text.contains("「使いすぎかも」"), "単独の感想はそのまま述べる: \(text)")
    }

    func testUnlockLineSpeaksOfUnlockedTimeNotUsedTime() {
        let s = record("2027-01-13 10:00", purpose: .contact, outcome: .wantsToUse, unlocked: true)
        s.temporaryUnlockEndedAt = jst("2027-01-13 10:03")
        let text = build(.night).lines.joined()
        XCTAssertTrue(text.contains("解除していた時間"), text)
        XCTAssertFalse(text.contains("使った時間"))
    }

    func testMorningAlwaysStartsWithYesterday() {
        XCTAssertEqual(build(.morning).lines.first, "昨日は、記録がまだありません。")
        for i in 0..<7 { record("2027-01-13 1\(i):00", purpose: .contact, outcome: .deferred) }
        for seed in ["a", "b", "c", "d"] {
            XCTAssertTrue(build(.morning, seed).lines[0].hasPrefix("昨日は、"), build(.morning, seed).lines[0])
        }
    }

    func testBuilderIsStableForTheSameSeed() {
        for i in 0..<4 { record("2027-01-13 1\(i):00", purpose: .contact, outcome: .deferred) }
        XCTAssertEqual(build(.night, "a"), build(.night, "a"))
    }

    func testBreakdownCountsPurposesAndAnsweredReflectionsOnly() {
        record("2027-01-13 10:00", purpose: .contact, reflection: .satisfied)
        record("2027-01-13 11:00", purpose: .contact, reflection: .skipped)
        record("2027-01-12 11:00", purpose: nil)
        record("2027-01-13 12:00", mode: .device, purpose: .research)
        let b = Breakdown.make(sessions: sessions(), mode: .demo, interval: cal.weekInterval(containing: jst("2027-01-13 20:00")))
        XCTAssertEqual(b.purposes.first(where: { $0.label == "連絡" })?.count, 2)
        XCTAssertEqual(b.purposes.first(where: { $0.label == Breakdown.noAnswer })?.count, 1)
        XCTAssertEqual(b.answeredReflections, 1, "「答えない」は感想の回答に数えない")
        XCTAssertEqual(b.purposes.first(where: { $0.label == "調べもの" })?.count, 0, "別モードは混ぜない")
    }

    func testMorningUsesTodayOnlyWhenDevelopmentFlagIsOn() {
        let now = jst("2027-01-13 08:00")
        XCTAssertEqual(ReflectionSchedule.contentRange(kind: .morning, now: now, calendar: cal, useTodayForMorning: true).dayWord, "今日")
        let normal = ReflectionSchedule.contentRange(kind: .morning, now: now, calendar: cal, useTodayForMorning: false)
        XCTAssertEqual(normal.dayWord, "昨日")
        XCTAssertEqual(normal.interval.start, jst("2027-01-12 04:00"))
    }

    func testCardIsSavedOnceAndNotRegeneratedOnEveryLaunch() {
        let store = ReflectionCardStore(context: context, now: { self.jst("2027-01-13 21:00") })
        var builds = 0
        func content() -> ReflectionContent { builds += 1; return ReflectionContent(title: "夜の振り返り", lines: ["a"]) }
        let first = store.ensureCard(mode: .demo, kind: .night, dayKey: "2027-01-13", content: content())
        let second = store.ensureCard(mode: .demo, kind: .night, dayKey: "2027-01-13", content: content())
        XCTAssertEqual(first.key, second.key)
        XCTAssertEqual(store.all().count, 1)
        store.dismiss(first)
        store.ensureCard(mode: .demo, kind: .night, dayKey: "2027-01-13", content: content())
        XCTAssertNotNil(store.card(mode: .demo, kind: .night, dayKey: "2027-01-13")?.dismissedAt)  // 閉じたら再表示しない
        // 別モード・別の日は別のカード
        store.ensureCard(mode: .device, kind: .night, dayKey: "2027-01-13", content: content())
        store.ensureCard(mode: .demo, kind: .night, dayKey: "2027-01-14", content: content())
        XCTAssertEqual(store.all().count, 3)
        // 開発用の作り直しは、閉じた状態を戻す
        let again = store.ensureCard(mode: .demo, kind: .night, dayKey: "2027-01-13", content: content(), regenerate: true)
        XCTAssertNil(again.dismissedAt)
    }

    // MARK: 期間ごとの集計（今週・今月・すべて）

    func testPeriodInsightsCountsAndSeparatesModes() {
        record("2027-01-12 09:00", purpose: .contact, outcome: .wantsToUse, reflection: .satisfied, unlocked: true)
        record("2027-01-12 23:00", purpose: .contact, outcome: .deferred, reflection: .skipped)
        record("2027-01-13 12:00", purpose: nil, outcome: .interrupted)
        record("2027-01-13 12:00", mode: .device, purpose: .research, outcome: .deferred)
        let w = PeriodInsights.make(sessions: sessions(), mode: .demo, period: .week, calendar: cal, now: jst("2027-01-13 20:00"))
        XCTAssertEqual(w.total, 3)
        XCTAssertEqual(w.wantsToUse, 1)
        XCTAssertEqual(w.deferred, 1)
        XCTAssertEqual(w.unlockStarted, 1)
        XCTAssertEqual(w.purposeCounts[.contact], 2)
        XCTAssertEqual(w.purposeSkipped, 1)
        XCTAssertEqual(w.answeredReflections, 1, "「答えない」は回答に数えない")
        XCTAssertEqual(w.bandCounts[.morning], 1)
        XCTAssertEqual(w.bandCounts[.night], 1)
    }

    func testWeekMonthAndAllCoverDifferentRanges() {
        record("2027-01-13 10:00")   // 今週
        record("2027-01-04 10:00")   // 今月・先週
        record("2026-12-20 10:00")   // 先月
        let now = jst("2027-01-13 20:00")
        func total(_ p: InsightPeriod) -> Int {
            PeriodInsights.make(sessions: sessions(), mode: .demo, period: p, calendar: cal, now: now).total
        }
        XCTAssertEqual(total(.week), 1)
        XCTAssertEqual(total(.month), 2)
        XCTAssertEqual(total(.all), 3)
        XCTAssertEqual(cal.monthInterval(containing: now).start, jst("2027-01-01 04:00"))
        XCTAssertEqual(cal.monthInterval(containing: jst("2027-01-01 02:00")).start, jst("2026-12-01 04:00"), "月初の深夜は前の月")
    }

    func testBandLabelsDoNotShowHours() {
        for band in TimeBand.allCases { XCTAssertFalse(band.label.contains("時"), band.label) }
    }

    // MARK: 設定改善の提案

    private func fill(_ n: Int, outcome: SessionOutcome, at hour: String = "12:00") {
        for i in 0..<n { record("2027-01-1\(1 + i % 3) \(hour)", outcome: outcome) }
    }

    func testNoSuggestionWithFewerThanFiveRecords() {
        fill(4, outcome: .wantsToUse)
        var state = SuggestionState()
        XCTAssertNil(SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo,
                                               preferences: Preferences(), calendar: cal, now: jst("2027-01-13 20:00")))
    }

    func testSuggestionNeedsFiveRecordsAndIsOncePerWeek() throws {
        fill(5, outcome: .wantsToUse)
        var prefs = Preferences(); prefs.waitSeconds = 60
        var state = SuggestionState()
        let now = jst("2027-01-13 20:00")
        let s = try XCTUnwrap(SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo,
                                                       preferences: prefs, calendar: cal, now: now))
        XCTAssertEqual(s.kind, .waitLonger)
        XCTAssertEqual(s.change, .waitSeconds(300))
        XCTAssertTrue(s.currentText.contains("1分") && s.proposedText.contains("5分"))
        // 回答するまで同じ提案を返し、回答後はその週は出さない
        XCTAssertEqual(SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo, preferences: prefs, calendar: cal, now: now), s)
        SuggestionEngine.resolve(state: &state, status: .skipped, now: now, calendar: cal.calendar)
        XCTAssertNil(SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo, preferences: prefs, calendar: cal, now: now.addingTimeInterval(3600)))
    }

    func testKeepingSuppressesSameSuggestionForAWhile() {
        fill(5, outcome: .wantsToUse)
        var prefs = Preferences(); prefs.waitSeconds = 60
        var state = SuggestionState()
        let now = jst("2027-01-13 20:00")
        _ = SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo, preferences: prefs, calendar: cal, now: now)
        SuggestionEngine.resolve(state: &state, status: .kept, now: now, calendar: cal.calendar)
        // 翌週でも、「今のまま」にした提案は出ない
        XCTAssertNil(SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo, preferences: prefs, calendar: cal, now: jst("2027-01-20 20:00")))
    }

    func testNightSuggestionIsBasedOnRecordsAfterNightTime() throws {
        for _ in 0..<5 { record("2027-01-12 22:30", outcome: .deferred) }
        var state = SuggestionState()
        let s = try XCTUnwrap(SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo,
                                                       preferences: Preferences(), calendar: cal, now: jst("2027-01-13 20:00")))
        XCTAssertEqual(s.kind, .nightEarlier)
        XCTAssertEqual(s.change, .nightMinute(20 * 60))
        XCTAssertTrue(s.evidence.contains("5件"))
    }

    func testNoSuggestionAtLargestWaitOption() {
        fill(6, outcome: .wantsToUse)
        var prefs = Preferences(); prefs.waitSeconds = Preferences.waitOptions.last
        var state = SuggestionState()
        XCTAssertNil(SuggestionEngine.evaluate(state: &state, sessions: sessions(), mode: .demo, preferences: prefs, calendar: cal, now: jst("2027-01-13 20:00")))
    }

    // MARK: 通知

    private func policy(quiet: Bool = true, gapHours: Double = 3) -> NotificationPolicy {
        var p = NotificationPolicy(calendar: cal.calendar)
        p.minimumGap = gapHours * 3600
        if !quiet { p.quietStartMinute = 0; p.quietEndMinute = 0 }
        return p
    }

    private func c(_ kind: NotificationKind, _ at: String) -> NotificationCandidate {
        NotificationCandidate(kind: kind, id: "\(kind.rawValue).\(at)", fireDate: jst(at))
    }

    func testQuietHoursAreDroppedNotBatchedToMorning() {
        let r = NotificationPlanner.select([c(.night, "2027-01-13 23:00"), c(.morning, "2027-01-14 07:59")], policy: policy())
        XCTAssertTrue(r.accepted.isEmpty)
        XCTAssertEqual(r.dropped.map(\.reason), [.quietHours, .quietHours])
        XCTAssertEqual(NotificationPlanner.select([c(.morning, "2027-01-14 08:00")], policy: policy()).accepted.count, 1)
    }

    func testMinimumGapIncludingAcrossMidnight() {
        let r = NotificationPlanner.select([c(.night, "2027-01-13 21:00"), c(.outing, "2027-01-13 19:00")], policy: policy())
        XCTAssertEqual(r.accepted.map(\.kind), [.night])
        XCTAssertEqual(r.dropped.first?.reason, .tooCloseToAnother)
        let cross = NotificationPlanner.select([c(.night, "2027-01-13 23:00"), c(.morning, "2027-01-14 01:00")], policy: policy(quiet: false))
        XCTAssertEqual(cross.accepted.count, 1, "日付をまたいでも3時間は空ける")
    }

    func testDailyLimitOfFour() {
        let items = ["09:00", "11:00", "13:00", "15:00", "17:00"].map { c(.outing, "2027-01-13 \($0)") }
        let r = NotificationPlanner.select(items, policy: policy(quiet: false, gapHours: 0))
        XCTAssertEqual(r.accepted.count, 4)
        XCTAssertEqual(r.dropped.first?.reason, .dailyLimit)
    }

    func testOutingsMayBeCloserToEachOtherThanToOtherNotifications() {
        let outings = NotificationPlanner.select([c(.outing, "2027-01-13 12:00"), c(.outing, "2027-01-13 13:30")], policy: policy(quiet: false))
        XCTAssertEqual(outings.accepted.count, 2, "お出かけどうしは、1時間半あければよい")
        let tooClose = NotificationPlanner.select([c(.outing, "2027-01-13 12:00"), c(.outing, "2027-01-13 12:45")], policy: policy(quiet: false))
        XCTAssertEqual(tooClose.accepted.count, 1)
        let withNight = NotificationPlanner.select([c(.night, "2027-01-13 21:00"), c(.outing, "2027-01-13 19:00")], policy: policy(quiet: false))
        XCTAssertEqual(withNight.accepted.map(\.kind), [.night], "朝夜の通知とは、3時間あける")
    }

    func testPostUseIsLowestPriorityAndOncePerDay() {
        let near = NotificationPlanner.select([c(.postUse, "2027-01-13 09:00"), c(.morning, "2027-01-13 08:00")], policy: policy())
        XCTAssertEqual(near.accepted.map(\.kind), [.morning], "朝の通知と近いときは追加しない")
        let two = NotificationPlanner.select([c(.postUse, "2027-01-13 12:00"), c(.postUse, "2027-01-13 18:00")], policy: policy())
        XCTAssertEqual(two.accepted.count, 1)
        XCTAssertEqual(two.dropped.first?.reason, .kindDailyLimit)
    }

    func testDuplicateIdsAreNotScheduledTwice() {
        let a = c(.night, "2027-01-13 21:00")
        XCTAssertEqual(NotificationPlanner.select([a, a], policy: policy()).accepted.count, 1)
    }

    func testRecurringIsEmptyByDefaultAndSkipsViewed() {
        let now = jst("2027-01-13 12:00")
        XCTAssertTrue(NotificationPlanner.recurring(preferences: Preferences(), now: now, calendar: cal, viewed: []).isEmpty)
        var prefs = Preferences(); prefs.notifyNight = true
        XCTAssertEqual(NotificationPlanner.recurring(preferences: prefs, now: now, calendar: cal, viewed: []).count, 2)
        let viewed = NotificationPlanner.recurring(preferences: prefs, now: now, calendar: cal, viewed: ["night.2027-01-13"])
        XCTAssertEqual(viewed.map { cal.dayKey(for: $0.fireDate) }, ["2027-01-14"])
        // 時刻を過ぎた今日の分は作らない
        XCTAssertEqual(NotificationPlanner.recurring(preferences: prefs, now: jst("2027-01-13 22:00"), calendar: cal, viewed: []).count, 1)
    }

    func testSettingsWarningsOnlyForMorningAndNightTooClose() {
        var prefs = Preferences()
        prefs.notifyMorning = true; prefs.morningMinute = 6 * 60      // 静かな時間は、もう無い
        prefs.notifyNight = true; prefs.nightMinute = 21 * 60
        XCTAssertTrue(NotificationPlanner.warnings(preferences: prefs, calendar: cal.calendar).isEmpty)
        prefs.nightMinute = 8 * 60
        XCTAssertTrue(NotificationPlanner.warnings(preferences: prefs, calendar: cal.calendar).joined().contains("3時間以内"))
    }

    // MARK: お出かけのおすすめ（回数だけ設定。時刻はランダム・均等）

    func testOutingTimesAreStableForADayAndDifferAcrossDays() {
        let window = (start: 11 * 60, end: 18 * 60)
        let a = OutingSchedule.minutes(count: 2, dayKey: "2027-01-13", window: window)
        XCTAssertEqual(a, OutingSchedule.minutes(count: 2, dayKey: "2027-01-13", window: window), "同じ日は、予約し直しても同じ時刻")
        let days = (1...20).map { OutingSchedule.minutes(count: 1, dayKey: "2027-01-\(String(format: "%02d", $0))", window: window)[0] }
        XCTAssertGreaterThan(Set(days).count, 10, "日ごとに、ばらける（ランダム）")
    }

    func testOutingTimesStayInsideTheWindowAndAreSpacedEvenly() {
        let window = (start: 9 * 60, end: 20 * 60)
        for day in 1...60 {
            let key = "2027-02-\(day)"
            for count in 1...6 {
                let times = OutingSchedule.minutes(count: count, dayKey: key, window: window)
                XCTAssertEqual(times.count, count)
                XCTAssertTrue(times.allSatisfy { $0 >= window.start && $0 <= window.end }, "\(key) \(times)")
                for pair in zip(times, times.dropFirst()) {
                    XCTAssertGreaterThanOrEqual(pair.1 - pair.0, OutingSchedule.gapMinutes, "お出かけどうしは1時間半以上あける \(times)")
                }
            }
        }
    }

    func testOutingCountIsReducedWhenTheWindowIsTooSmallForTheGap() {
        let tight = OutingSchedule.minutes(count: 6, dayKey: "2027-03-01", window: (start: 11 * 60, end: 17 * 60))
        XCTAssertEqual(tight.count, 4, "6時間の枠には、1時間半あけて4回まで")
        XCTAssertEqual(OutingSchedule.minutes(count: 3, dayKey: "2027-03-01", window: (start: 12 * 60, end: 13 * 60)).count, 1)
    }

    func testOutingWindowKeepsThreeHoursFromMorningAndNightNotifications() {
        var prefs = Preferences()
        prefs.notifyMorning = true; prefs.morningMinute = 8 * 60
        prefs.notifyNight = true; prefs.nightMinute = 21 * 60
        let window = OutingSchedule.window(preferences: prefs)
        XCTAssertEqual(window.start, 11 * 60)
        XCTAssertEqual(window.end, 18 * 60)
    }

    func testRecurringCreatesOneCandidatePerOutingAndPreferencesClampTheCount() throws {
        var prefs = Preferences()
        prefs.notifyOuting = true; prefs.outingPerDay = 2
        let list = NotificationPlanner.recurring(preferences: prefs, now: jst("2027-01-13 06:00"), calendar: cal, viewed: [])
        let today = list.filter { cal.dayKey(for: $0.fireDate) == "2027-01-13" }
        XCTAssertEqual(today.filter { $0.kind == .outing }.count, 2)
        XCTAssertEqual(Set(list.map(\.id)).count, list.count, "識別子は重ならない")
        let clamped = try JSONDecoder().decode(Preferences.self, from: Data(#"{"outingPerDay":9}"#.utf8))
        XCTAssertEqual(clamped.outingPerDay, 6)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8)).outingPerDay, 1)
    }

    func testMorningAndNightCardsAreAlwaysEnabledEvenIfSavedOff() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data(#"{"morningEnabled":false,"nightEnabled":false}"#.utf8))
        XCTAssertTrue(p.morningEnabled)
        XCTAssertTrue(p.nightEnabled)
    }

    func testPreferencesDecodeWithMissingKeys() throws {
        let p = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(p.notifyMorning || p.notifyNight || p.notifyPostUse || p.notifyOuting, "通知は初期状態ですべてオフ")
        XCTAssertEqual(p.quietStartMinute, 22 * 60)
        XCTAssertEqual(p.quietEndMinute, 8 * 60)
    }

    // MARK: 履歴の言い方・解除時間・日別集計

    func testResultTitlesAreSelfExplanatory() {
        XCTAssertEqual(record("2027-01-13 10:00", outcome: .deferred).resultTitle, "やめた")
        XCTAssertEqual(record("2027-01-13 10:00", outcome: .interrupted).resultTitle, "途中でやめた")
        XCTAssertEqual(record("2027-01-13 10:00", outcome: .wantsToUse).resultTitle, "使いたいと答えた")
        XCTAssertEqual(record("2027-01-13 10:00", outcome: .wantsToUse, unlocked: true).resultTitle, "解除した")
    }

    func testUnlockDurationIsTimeUnlockedNotTimeUsed() {
        let s = record("2027-01-13 10:00", outcome: .wantsToUse, unlocked: true)
        XCTAssertEqual(s.unlockDurationText, "解除中")
        XCTAssertTrue(s.isUnlockInProgress)
        s.temporaryUnlockEndedAt = jst("2027-01-13 10:00").addingTimeInterval(40)
        XCTAssertEqual(s.unlockDurationText, "解除 1分未満")
        s.temporaryUnlockEndedAt = jst("2027-01-13 10:03")
        XCTAssertEqual(s.unlockDurationText, "解除 約3分")
        XCTAssertNil(record("2027-01-13 10:00", outcome: .deferred).unlockDurationText)
    }

    func testUnlockEndIsRecordedOnceAndNotBeforeStart() {
        let store = SessionStore(context: context, now: { self.jst("2027-01-13 10:00") })
        let s = record("2027-01-13 10:00", outcome: .wantsToUse, unlocked: true)
        store.recordTemporaryUnlockEnd(s, at: jst("2027-01-13 09:00"))   // 開始より前なら開始に揃える
        XCTAssertEqual(s.temporaryUnlockEndedAt, jst("2027-01-13 10:00"))
        store.recordTemporaryUnlockEnd(s, at: jst("2027-01-13 10:20"))
        XCTAssertEqual(s.temporaryUnlockEndedAt, jst("2027-01-13 10:00"), "2回目は上書きしない")
    }

    func testUnlockWindowRespectsAppleMinimumAndLongSettings() {
        XCTAssertEqual(Preferences.unlockWindowSeconds(minutes: 1), 16 * 60, "最短15分を下回らない")
        XCTAssertEqual(Preferences.unlockWindowSeconds(minutes: 15), 16 * 60)
        XCTAssertEqual(Preferences.unlockWindowSeconds(minutes: 30), 31 * 60, "長い設定は、使わなくても約その分で戻る")
        XCTAssertEqual(Preferences.unlockMinuteOptions, [1, 5, 10, 30], "解除する時間は、この4つだけ")
        var p = Preferences(); p.unlockMinutes = 99
        XCTAssertEqual(p.effectiveUnlockMinutes, 30, "選択肢にない値は、いちばん近いものに寄せる")
        p.unlockMinutes = 0
        XCTAssertEqual(p.effectiveUnlockMinutes, 1)
        p.unlockMinutes = 7
        XCTAssertEqual(p.effectiveUnlockMinutes, 5)
        XCTAssertEqual(Preferences().effectiveUnlockMinutes, Preferences.defaultUnlockMinutes)
        XCTAssertTrue(Preferences.unlockMinuteOptions.contains(Preferences.defaultUnlockMinutes))

        XCTAssertEqual(Preferences.waitOptions, [10, 30, 60, 300, 600, 1800], "待機時間は、10秒・30秒に加えて、この4つ")
        var w = Preferences(); w.waitSeconds = 180
        XCTAssertEqual(w.effectiveWaitSeconds, 60, "以前の3分は、近い選択肢に寄せる（180は、60と300の間で、60に近い）")
        w.waitSeconds = 120
        XCTAssertEqual(w.effectiveWaitSeconds, 60)
        w.waitSeconds = 20
        XCTAssertTrue([10.0, 30.0].contains(w.effectiveWaitSeconds))
        XCTAssertTrue(Preferences.waitOptions.contains(Preferences.defaultWaitSeconds))
    }

    func testOutingMessagesAreGentleAndVaried() {
        XCTAssertGreaterThanOrEqual(OutingMessages.all.count, 11)
        XCTAssertEqual(Set(OutingMessages.all).count, OutingMessages.all.count, "重複しない")
        for text in OutingMessages.all {
            for banned in ["使いすぎ", "連続", "途切れ", "ダメ", "だめ", "急い", "早く"] {
                XCTAssertFalse(text.contains(banned), text)
            }
            XCTAssertFalse(text.unicodeScalars.contains { ("0"..."9").contains($0) }, "数字を入れない: \(text)")
        }
        XCTAssertEqual(OutingMessages.pick(seed: "futo.outing.2027-01-13"), OutingMessages.pick(seed: "futo.outing.2027-01-13"))
        let week = (10...20).map { OutingMessages.pick(seed: "futo.outing.2027-01-\($0)") }
        XCTAssertGreaterThan(Set(week).count, 3, "日が変わると、いろいろな文言が出る")
    }

    func testCountdownStartsFromTheFullNumberOfSeconds() {
        XCTAssertEqual(countdownText(10), "10", "10秒なら、10から始まる")
        XCTAssertEqual(countdownText(9.2), "10", "切り上げ")
        XCTAssertEqual(countdownText(1), "1")
        XCTAssertEqual(countdownText(0), "0")
        XCTAssertEqual(countdownText(59.01), "1:00")
        XCTAssertEqual(countdownText(60), "1:00")
        XCTAssertEqual(countdownText(90), "1:30")
        XCTAssertEqual(countdownText(1_800), "30:00")
    }
}
