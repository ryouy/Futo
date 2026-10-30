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

final class ShareMessageTests: XCTestCase {
    func testNormalizedTrimsLimitsAndDropsControlCharacters() {
        XCTAssertEqual(ShareMessage.normalized("  今週は、がんばった！ \n"), "今週は、がんばった！")
        XCTAssertEqual(ShareMessage.normalized(String(repeating: "あ", count: 80))?.count, 60)
        XCTAssertEqual(ShareMessage.normalized("a\u{0}b"), "ab")
        XCTAssertNil(ShareMessage.normalized("   "))
        XCTAssertNil(ShareMessage.normalized(""))
    }

    func testLinksAreRecognizedLikeTheServerDoes() {
        XCTAssertTrue(ShareMessage.looksLikeLink("見て https://evil.example/x"))
        XCTAssertTrue(ShareMessage.looksLikeLink("www.example.com へ"))
        XCTAssertTrue(ShareMessage.looksLikeLink("pay me at evil.com"))
        XCTAssertFalse(ShareMessage.looksLikeLink("今週は少しがんばった！"))
        XCTAssertFalse(ShareMessage.looksLikeLink("3.5時間減った"))
    }

    func testMessageIsOnlyAttachedToFriendPayloads() throws {
        var selection = ShareSelection(); selection.counts = true; selection.message = "こんにちは"; selection.phrase = .p1
        let web = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, expiresInDays: 7)
        XCTAssertNil(web.message, "公開リンクには、自由入力の一言を付けない")
        XCTAssertEqual(web.phraseId, "p1")
        let friend = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, expiresInDays: nil, recipientUids: ["u1"], allowsMessage: true)
        XCTAssertEqual(friend.message, "こんにちは")
        XCTAssertNil(friend.phraseId, "フレンド共有では、一言は1つだけ")
        XCTAssertEqual(friend.updateBody.message, "こんにちは")
    }

    func testStandingConfigRemembersTheMessage() {
        var selection = ShareSelection(); selection.counts = true; selection.message = "  また来週 "
        let config = StandingShareConfig(shareId: "S", period: .thisWeek, selection: selection, refreshedAt: Date())
        XCTAssertEqual(config.selection.message, "また来週")
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

@MainActor
final class AppUsageSummaryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func unlock(daysAgo: Double, mode: AppMode = .device, outcome: SessionOutcome = .wantsToUse, unlocked: Bool = true) -> Session {
        let at = now.addingTimeInterval(-daysAgo * 86_400)
        let s = Session(mode: mode, startedAt: at.addingTimeInterval(-100), requiredWaitSeconds: 60)
        s.phase = .completed; s.outcome = outcome
        if unlocked { s.temporaryUnlockStartedAt = at }
        return s
    }

    private func top(_ list: [(Session, [String])], names: [String: String?], interval: DateInterval? = nil) -> [AppCount] {
        let map = Dictionary(uniqueKeysWithValues: list.map { ($0.0.id, $0.1) })
        return AppUsageSummary.top(sessions: list.map(\.0), mode: .device, interval: interval, keys: { map[$0.id] ?? [] }, name: { names[$0] ?? nil })
    }

    func testCountsPerAppSortedAndLimitedToTen() {
        var list: [(Session, [String])] = []
        for i in 0..<12 { for _ in 0...(11 - i) { list.append((unlock(daysAgo: 1), ["a\(i)"])) } }
        let names = Dictionary(uniqueKeysWithValues: (0..<12).map { ("a\($0)", Optional("App\($0)")) })
        let result = top(list, names: names)
        XCTAssertEqual(result.count, 10)
        XCTAssertEqual(result.first, AppCount(name: "App0", count: 12))
        XCTAssertEqual(result.map(\.count), result.map(\.count).sorted(by: >))
    }

    func testUnreadableNamesAreLeftOutNeverGuessed() {
        let list = [(unlock(daysAgo: 1), ["known"]), (unlock(daysAgo: 1), ["secret"])]
        let result = top(list, names: ["known": "動画", "secret": nil])
        XCTAssertEqual(result, [AppCount(name: "動画", count: 1)])
        XCTAssertTrue(top(list, names: ["known": nil, "secret": nil]).isEmpty)
    }

    func testOnlyRealUnlocksOfTheDeviceInThePeriodCount() {
        let inRange = unlock(daysAgo: 2)
        let old = unlock(daysAgo: 40)
        let deferred = unlock(daysAgo: 1, outcome: .deferred, unlocked: false)
        let noUnlock = unlock(daysAgo: 1, unlocked: false)
        let demo = unlock(daysAgo: 1, mode: .demo)
        let list = [(inRange, ["a"]), (old, ["a"]), (deferred, ["a"]), (noUnlock, ["a"]), (demo, ["a"])]
        let week = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        XCTAssertEqual(top(list, names: ["a": "SNS"], interval: week), [AppCount(name: "SNS", count: 1)])
        XCTAssertEqual(top(list, names: ["a": "SNS"], interval: nil).first?.count, 2, "全期間なら、古い解除も数える")
    }

    func testSameNameIsMergedAndNamesAreCleaned() {
        let list = [(unlock(daysAgo: 1), ["x"]), (unlock(daysAgo: 1), ["y"])]
        XCTAssertEqual(top(list, names: ["x": " SNS\n", "y": "SNS"]), [AppCount(name: "SNS", count: 2)])
        XCTAssertEqual(AppUsageSummary.cleanName(String(repeating: "あ", count: 80))?.count, 40)
        XCTAssertNil(AppUsageSummary.cleanName("  \n "))
    }

    func testPayloadIncludesAppsByDefaultAndOnlyWhenNamesWereRead() throws {
        var selection = ShareSelection()
        selection.counts = true
        XCTAssertTrue(selection.apps, "初期は、アプリ名を含める")
        let with = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, now: now,
                                              appCounts: { _ in [AppCount(name: "動画", count: 3)] })
        XCTAssertEqual(with.apps, [AppCount(name: "動画", count: 3)])
        XCTAssertEqual(with.updateBody.apps, with.apps)
        let without = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, now: now)
        XCTAssertNil(without.apps, "名前を読み取れなければ、項目ごと付けない")
        selection.apps = false
        let off = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, now: now,
                                             appCounts: { _ in [AppCount(name: "動画", count: 3)] })
        XCTAssertNil(off.apps, "オフなら、名前は送らない")
    }

    func testAppsOnlySelectionWithNoReadableNamesCannotBeShared() {
        var selection = ShareSelection()
        selection.apps = true
        XCTAssertThrowsError(try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, now: now)) {
            XCTAssertEqual($0 as? ShareStatsBuilder.BuildError, .nothingSelected)
        }
    }
}
