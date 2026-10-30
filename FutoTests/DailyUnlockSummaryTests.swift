import XCTest
@testable import Futo

@MainActor
final class DailyUnlockSummaryTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }()

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// 一時解除を始めたひと呼吸
    private func unlock(at: Date, mode: AppMode = .device, items: [String]) -> (Session, [String]) {
        let s = Session(mode: mode, startedAt: at.addingTimeInterval(-200), requiredWaitSeconds: 180)
        s.phase = .completed; s.outcome = .wantsToUse
        s.completedAt = at; s.temporaryUnlockStartedAt = at
        return (s, items)
    }

    private func make(_ list: [(Session, [String])], mode: AppMode = .device, interval: DateInterval? = nil) -> [DailyUnlockSummary.Day<String>] {
        let map = Dictionary(uniqueKeysWithValues: list.map { ($0.0.id, $0.1) })
        return DailyUnlockSummary.make(sessions: list.map(\.0), mode: mode, interval: interval, calendar: calendar) { map[$0.id] ?? [] }
    }

    func testGroupsByDayThenAppAndCountsUnlocks() {
        let days = make([
            unlock(at: date(2026, 10, 30, 9), items: ["A"]),
            unlock(at: date(2026, 10, 30, 13), items: ["A"]),
            unlock(at: date(2026, 10, 30, 20), items: ["B"]),
            unlock(at: date(2026, 10, 29, 22), items: ["A"]),
        ])
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].unlockCount, 3)
        XCTAssertEqual(days[0].rows.map { $0.key ?? "?" }, ["A", "B"], "回数の多い順")
        XCTAssertEqual(days[0].rows.map(\.count), [2, 1])
        XCTAssertEqual(days[1].rows.first?.count, 1)
        XCTAssertGreaterThan(days[0].day, days[1].day, "新しい日が先")
    }

    func testOneUnlockOfSeveralAppsCountsOncePerAppButOnceForTheDay() {
        let days = make([unlock(at: date(2026, 10, 30, 9), items: ["A", "B"])])
        XCTAssertEqual(days[0].unlockCount, 1)
        XCTAssertEqual(Set(days[0].rows.map { $0.key ?? "?" }), ["A", "B"])
        XCTAssertEqual(days[0].rows.map(\.count), [1, 1])
    }

    func testDeferredInterruptedAndOpenBreathsAreNotCounted() {
        let deferred = Session(mode: .device, startedAt: date(2026, 10, 30, 9), requiredWaitSeconds: 60)
        deferred.phase = .completed; deferred.outcome = .deferred
        let interrupted = Session(mode: .device, startedAt: date(2026, 10, 30, 10), requiredWaitSeconds: 60)
        interrupted.phase = .interrupted; interrupted.outcome = .interrupted
        let wantsButNoUnlock = Session(mode: .device, startedAt: date(2026, 10, 30, 11), requiredWaitSeconds: 60)
        wantsButNoUnlock.phase = .completed; wantsButNoUnlock.outcome = .wantsToUse   // 解除に失敗した
        let open = Session(mode: .device, startedAt: date(2026, 10, 30, 12), requiredWaitSeconds: 60)
        let days = DailyUnlockSummary.make(sessions: [deferred, interrupted, wantsButNoUnlock, open], mode: .device, interval: nil, calendar: calendar) { _ in ["A"] }
        XCTAssertTrue(days.isEmpty, "一時解除を始めたものだけが対象")
    }

    func testDemoAndDeviceAreSeparated() {
        let list = [unlock(at: date(2026, 10, 30, 9), mode: .demo, items: ["D"]), unlock(at: date(2026, 10, 30, 9), items: ["A"])]
        XCTAssertEqual(make(list, mode: .device).first?.rows.map { $0.key ?? "?" }, ["A"])
        XCTAssertEqual(make(list, mode: .demo).first?.rows.map { $0.key ?? "?" }, ["D"])
    }

    func testDaysAreCutAtLocalMidnightNotUTC() {
        // 日本時間で 0:30 と 23:30：UTCでは同じ日・別の日にまたがるが、現地の日付で分ける
        let days = make([unlock(at: date(2026, 10, 30, 0, 30), items: ["A"]), unlock(at: date(2026, 10, 29, 23, 30), items: ["A"])])
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(calendar.component(.day, from: days[0].day), 30)
        XCTAssertEqual(calendar.component(.day, from: days[1].day), 29)
    }

    func testUnlocksWithoutRecordedTargetsGetOneHonestUnknownRow() {
        let days = make([unlock(at: date(2026, 10, 30, 9), items: []), unlock(at: date(2026, 10, 30, 10), items: [])])
        XCTAssertEqual(days[0].rows.count, 1)
        XCTAssertNil(days[0].rows[0].key, "名前を推測しない")
        XCTAssertEqual(days[0].rows[0].count, 2)
    }

    func testPeriodFilterUsesTheUnlockTime() {
        let list = [unlock(at: date(2026, 10, 30, 9), items: ["A"]), unlock(at: date(2026, 10, 20, 9), items: ["A"])]
        let week = DateInterval(start: date(2026, 10, 26, 0), end: date(2026, 11, 2, 0))
        XCTAssertEqual(make(list, interval: week).count, 1)
    }

    func testOriginalTimesAreKeptForTheDetailList() {
        let a = unlock(at: date(2026, 10, 30, 9), items: ["A"])
        let b = unlock(at: date(2026, 10, 30, 13), items: ["A"])
        let days = make([a, b])
        let times = days[0].rows[0].sessions.compactMap(\.temporaryUnlockStartedAt)
        XCTAssertEqual(times, [date(2026, 10, 30, 13), date(2026, 10, 30, 9)], "詳細では、新しい順に、元の時刻が見られる")
    }

    func testManyAppsStillProduceOneRowEach() {
        let list = (0..<40).map { unlock(at: date(2026, 10, 30, 9, $0), items: ["App\($0)"]) }
        let days = make(list)
        XCTAssertEqual(days[0].rows.count, 40)
        XCTAssertEqual(days[0].unlockCount, 40)
    }
}
