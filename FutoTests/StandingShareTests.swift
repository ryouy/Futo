import XCTest
@testable import Futo

final class StandingShareTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "standing-tests-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testConfigKeepsOnlyTheChoicesNotTheStats() throws {
        var selection = ShareSelection()
        selection.counts = true; selection.feelings = true; selection.showName = false; selection.phrase = .p2
        let config = StandingShareConfig(shareId: "S1", period: .all, selection: selection, refreshedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(config.selection, selection)
        XCTAssertEqual(config.sharePeriod, .all)
        let json = String(data: try JSONEncoder().encode(config), encoding: .utf8)!
        XCTAssertFalse(json.contains("wantsToUse"), "統計の値は、端末にも保存しない")
    }

    func testRefreshIsDueOnlyAfterTheInterval() {
        let config = StandingShareConfig(shareId: "S1", period: .thisWeek, selection: ShareSelection(), refreshedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertFalse(config.isDue(now: Date(timeIntervalSince1970: 1_000 + 3_599)))
        XCTAssertTrue(config.isDue(now: Date(timeIntervalSince1970: 1_000 + 3_600)))
    }

    func testStoreIsPerAccountAndEmptyingRemovesIt() {
        let store = UserDefaultsStandingStore(defaults: defaults())
        let a = StandingShareConfig(shareId: "A", period: .lastWeek, selection: ShareSelection(), refreshedAt: Date())
        store.save([a], uid: "uid-1")
        XCTAssertEqual(store.load(uid: "uid-1"), [a])
        XCTAssertEqual(store.load(uid: "uid-2"), [], "別のアカウントには見えない")
        store.save([], uid: "uid-1")
        XCTAssertEqual(store.load(uid: "uid-1"), [])
    }

    func testUpdateBodyHasNoRecipientsKeyOrExpiry() throws {
        var selection = ShareSelection(); selection.counts = true
        let payload = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, expiresInDays: 7, recipientUids: ["u1"])
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload.updateBody)) as! [String: Any]
        XCTAssertNil(object["recipientUids"])
        XCTAssertNil(object["expiresInDays"])
        XCTAssertNil(object["idempotencyKey"])
        XCTAssertNotNil(object["counts"])
        XCTAssertNil(object["purposes"], "選ばなかった項目は、キー自体を送らない")
    }
}

@MainActor
final class AllPeriodStatsTests: XCTestCase {
    private func make(_ start: Date, outcome: SessionOutcome = .deferred, purpose: Purpose? = .research) -> Session {
        let s = Session(mode: .device, startedAt: start, requiredWaitSeconds: 60)
        s.phase = .completed; s.outcome = outcome; s.purpose = purpose
        return s
    }

    func testAllPeriodCountsEveryClosedRecordFromTheFirstOne() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let old = make(now.addingTimeInterval(-400 * 86_400))
        let recent = make(now.addingTimeInterval(-2 * 86_400), outcome: .wantsToUse)
        let open = Session(mode: .device, startedAt: now.addingTimeInterval(-100), requiredWaitSeconds: 60)
        var selection = ShareSelection(); selection.counts = true; selection.purposes = true
        let payload = try ShareStatsBuilder.make(sessions: [old, recent, open], mode: .device, period: .all, selection: selection, now: now)
        XCTAssertEqual(payload.period, "all")
        XCTAssertEqual(payload.counts?.deferred, 1)
        XCTAssertEqual(payload.counts?.wantsToUse, 1)
        XCTAssertEqual(payload.purposes?.research, 2)
        XCTAssertFalse(payload.isPartial)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let start = try XCTUnwrap(formatter.date(from: payload.periodStart))
        XCTAssertEqual(start.timeIntervalSince1970, old.startedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testAllPeriodWithNoRecordsStillHasAValidRangeAndIgnoresDemo() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let demo = Session(mode: .demo, startedAt: now.addingTimeInterval(-86_400), requiredWaitSeconds: 60)
        demo.phase = .completed; demo.outcome = .wantsToUse
        var selection = ShareSelection(); selection.counts = true
        let payload = try ShareStatsBuilder.make(sessions: [demo], mode: .device, period: .all, selection: selection, now: now)
        XCTAssertEqual(payload.counts, SharePayload.Counts(wantsToUse: 0, deferred: 0, interrupted: 0))
        XCTAssertLessThan(payload.periodStart, payload.periodEnd)
    }

    func testAllPeriodNeverExceedsTenYears() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ancient = make(now.addingTimeInterval(-5_000 * 86_400))
        var selection = ShareSelection(); selection.counts = true
        let payload = try ShareStatsBuilder.make(sessions: [ancient], mode: .device, period: .all, selection: selection, now: now)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let span = formatter.date(from: payload.periodEnd)!.timeIntervalSince(formatter.date(from: payload.periodStart)!)
        XCTAssertLessThanOrEqual(span, 3_650 * 86_400)
        XCTAssertEqual(payload.counts?.deferred, 0, "10年より前の記録は、範囲の外")
    }
}
