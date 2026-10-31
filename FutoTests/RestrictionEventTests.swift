import SwiftData
import XCTest
@testable import Futo

@MainActor
final class RestrictionEventTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        container = try ModelContainer(for: Session.self, ReflectionCard.self, RestrictionEvent.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func event(_ kind: RestrictionEventKind, mode: AppMode = .device, daysAgo: Double = 0, minutes: Int? = nil) -> RestrictionEvent {
        RestrictionEvent(mode: mode, kind: kind, at: now.addingTimeInterval(-daysAgo * 86_400), minutes: minutes)
    }

    func testCountsSeparatePausesAndEndsByModeAndPeriod() {
        let events = [event(.pause, minutes: 30), event(.pause, daysAgo: 2, minutes: 30), event(.pause, daysAgo: 30, minutes: 30),
                      event(.end), event(.end, mode: .demo), event(.pause, mode: .demo)]
        let week = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now.addingTimeInterval(1))
        XCTAssertEqual(RestrictionEventSummary.counts(events, mode: .device, interval: week), .init(pauses: 2, ends: 1))
        XCTAssertEqual(RestrictionEventSummary.counts(events, mode: .device, interval: nil), .init(pauses: 3, ends: 1))
        XCTAssertEqual(RestrictionEventSummary.counts(events, mode: .demo, interval: nil), .init(pauses: 1, ends: 1))
        XCTAssertTrue(RestrictionEventSummary.counts([], mode: .device, interval: nil).isEmpty)
    }

    func testStoreRecordsAndDeletes() {
        let store = RestrictionEventStore(context: context, now: { self.now })
        store.record(.pause, mode: .device, minutes: 30)
        store.record(.end, mode: .device)
        XCTAssertEqual(store.all().count, 2)
        XCTAssertEqual(store.all().first { $0.kind == .pause }?.minutes, 30)
        store.deleteAll()
        XCTAssertTrue(store.all().isEmpty)
    }

    func testEventsAreNotMixedIntoUnlockRecords() {
        // 制限の管理の記録は、Sessionとは別。解除（見送り・利用）の集計には入らない
        let store = RestrictionEventStore(context: context, now: { self.now })
        store.record(.pause, mode: .device, minutes: 30)
        let days = DailyUnlockSummary.make(sessions: (try? context.fetch(FetchDescriptor<Session>())) ?? [], mode: .device, interval: nil) { (_: Session) -> [String] in [] }
        XCTAssertTrue(days.isEmpty)
    }

    func testShareCountsAreOnlyIncludedWhenSelected() throws {
        var selection = ShareSelection(); selection.counts = true
        let off = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, now: now,
                                             restrictionCounts: { _ in RestrictionCounts(pauses: 2, ends: 1) })
        XCTAssertNil(off.restriction, "初期は、含めない")
        selection.restriction = true
        let on = try ShareStatsBuilder.make(sessions: [], mode: .device, period: .thisWeek, selection: selection, now: now,
                                            restrictionCounts: { _ in RestrictionCounts(pauses: 2, ends: 1) })
        XCTAssertEqual(on.restriction, RestrictionCounts(pauses: 2, ends: 1))
        XCTAssertEqual(on.updateBody.restriction, on.restriction)
    }

    func testBackupCarriesDeviceEventsAndRestoresWithoutDuplicates() throws {
        let kept = event(.pause, minutes: 30)
        let demo = event(.end, mode: .demo)
        context.insert(kept); context.insert(demo)
        let doc = BackupDocument.make(sessions: [], cards: [], preferences: Preferences(), theme: nil, language: nil, events: [kept, demo])
        XCTAssertEqual(doc.restrictionEvents?.map(\.id), [kept.id], "デモの記録は入れない")
        let parsed = try BackupDocument.parse(try doc.encoded())
        XCTAssertEqual(parsed.restrictionEvents?.count, 1)

        let otherContainer = try ModelContainer(for: Session.self, ReflectionCard.self, RestrictionEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let other = otherContainer.mainContext
        func restore() -> Int {
            let ids = Set(((try? other.fetch(FetchDescriptor<RestrictionEvent>())) ?? []).map(\.id))
            let plan = BackupMergePlan.make(document: parsed, existingSessionIDs: [], existingCardKeys: [], existingEventIDs: ids)
            XCTAssertTrue(BackupRestorer.apply(plan, to: other))
            return plan.newEvents.count
        }
        XCTAssertEqual(restore(), 1)
        XCTAssertEqual(restore(), 0)
        XCTAssertEqual(try other.fetch(FetchDescriptor<RestrictionEvent>()).count, 1)
    }

    func testOlderBackupsWithoutEventsStillLoad() throws {
        var doc = BackupDocument.make(sessions: [], cards: [], preferences: Preferences(), theme: nil, language: nil)
        doc.restrictionEvents = nil
        let parsed = try BackupDocument.parse(try doc.encoded())
        XCTAssertNil(parsed.restrictionEvents)
        let plan = BackupMergePlan.make(document: parsed, existingSessionIDs: [], existingCardKeys: [])
        XCTAssertTrue(plan.newEvents.isEmpty)
    }
}
