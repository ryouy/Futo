import SwiftData
import XCTest
@testable import Futo

@MainActor
final class BackupDocumentTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        container = try ModelContainer(for: Session.self, ReflectionCard.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func session(mode: AppMode = .device, phase: SessionPhase = .completed, at: Date = Date(timeIntervalSince1970: 1_800_000_000)) -> Session {
        let s = Session(mode: mode, startedAt: at, requiredWaitSeconds: 180)
        s.phase = phase
        s.purpose = .research
        s.outcome = phase == .completed ? .wantsToUse : nil
        s.completedAt = at.addingTimeInterval(200)
        s.reflection = .satisfied
        s.temporaryUnlockedApps = Data("SECRET-OS-TOKEN".utf8)
        context.insert(s)
        return s
    }

    func testBackupHasOnlyClosedDeviceRecordsAndNoOSTokens() throws {
        let kept = session()
        _ = session(mode: .demo)
        _ = session(phase: .waiting)
        let doc = BackupDocument.make(sessions: [kept] + (try context.fetch(FetchDescriptor<Session>())).filter { $0.id != kept.id },
                                      cards: [], preferences: Preferences(), theme: "green", language: "ja")
        XCTAssertEqual(doc.sessions.count, 1, "デモ・途中の記録は入れない")
        XCTAssertEqual(doc.sessions.first?.id, kept.id)
        let json = String(data: try doc.encoded(), encoding: .utf8)!
        XCTAssertFalse(json.contains("SECRET"), "OSのトークンは入れない")
        XCTAssertFalse(json.contains("temporaryUnlockedApps"))
        XCTAssertFalse(json.lowercased().contains("token"))
    }

    func testRoundTrip() throws {
        let s = session()
        let doc = BackupDocument.make(sessions: [s], cards: [], preferences: Preferences(), theme: "green", language: "en", now: Date(timeIntervalSince1970: 1_800_001_000))
        let parsed = try BackupDocument.parse(try doc.encoded())
        XCTAssertEqual(parsed, doc)
    }

    func testRejectsBrokenOversizedAndNewerBackups() throws {
        XCTAssertThrowsError(try BackupDocument.parse(Data("not json".utf8))) { XCTAssertEqual($0 as? BackupDocument.ParseError, .invalid) }
        XCTAssertThrowsError(try BackupDocument.parse(Data(count: BackupDocument.maxBytes + 1))) { XCTAssertEqual($0 as? BackupDocument.ParseError, .tooLarge) }
        XCTAssertThrowsError(try BackupDocument.parse(Data(#"{"schemaVersion":99,"future":{}}"#.utf8))) { XCTAssertEqual($0 as? BackupDocument.ParseError, .newerVersion) }
        var doc = BackupDocument.make(sessions: [], cards: [], preferences: Preferences(), theme: nil, language: nil)
        doc.schemaVersion = 0
        XCTAssertThrowsError(try BackupDocument.parse(try doc.encoded())) { XCTAssertEqual($0 as? BackupDocument.ParseError, .invalid) }
    }

    func testMergeAddsOnlyMissingAndNeverOverwrites() throws {
        let a = session(at: Date(timeIntervalSince1970: 1_800_000_000))
        let b = session(at: Date(timeIntervalSince1970: 1_800_100_000))
        let doc = BackupDocument.make(sessions: [a, b], cards: [], preferences: Preferences(), theme: nil, language: nil)
        let plan = BackupMergePlan.make(document: doc, existingSessionIDs: [a.id], existingCardKeys: [])
        XCTAssertEqual(plan.newSessions.map(\.id), [b.id])
        XCTAssertEqual(plan.skippedSessions, 1)
    }

    func testMergeDropsOpenAndInvalidRecords() {
        let open = BackupDocument.SessionRecord(id: UUID(), startedAt: Date(), purpose: nil, requiredWaitSeconds: 180, phase: .waiting, outcome: nil)
        let bad = BackupDocument.SessionRecord(id: UUID(), startedAt: Date(), purpose: nil, requiredWaitSeconds: -5, phase: .completed, outcome: .deferred)
        let huge = BackupDocument.SessionRecord(id: UUID(), startedAt: Date(), purpose: nil, requiredWaitSeconds: 1e9, phase: .completed, outcome: .deferred)
        let doc = BackupDocument(schemaVersion: 1, createdAt: Date(), sessions: [open, bad, huge], cards: [], preferences: Preferences(), theme: nil, language: nil)
        XCTAssertTrue(BackupMergePlan.make(document: doc, existingSessionIDs: [], existingCardKeys: []).newSessions.isEmpty)
    }

    func testMergeIgnoresDemoCardsAndKeepsExistingCards() {
        let demo = BackupDocument.CardRecord(key: "demo|morning|2026-01-01", kind: .morning, dayKey: "2026-01-01", title: "t", body: "b", createdAt: Date())
        let existing = BackupDocument.CardRecord(key: "device|morning|2026-01-02", kind: .morning, dayKey: "2026-01-02", title: "t", body: "b", createdAt: Date())
        let fresh = BackupDocument.CardRecord(key: "device|night|2026-01-02", kind: .night, dayKey: "2026-01-02", title: "t", body: "b", createdAt: Date())
        let doc = BackupDocument(schemaVersion: 1, createdAt: Date(), sessions: [], cards: [demo, existing, fresh], preferences: Preferences(), theme: nil, language: nil)
        let plan = BackupMergePlan.make(document: doc, existingSessionIDs: [], existingCardKeys: [existing.key])
        XCTAssertEqual(plan.newCards.map(\.key), [fresh.key])
    }

    func testRestoreIsIdempotentAndKeepsExistingData() throws {
        let original = session()
        let doc = BackupDocument.make(sessions: [original], cards: [], preferences: Preferences(), theme: nil, language: nil)
        // 別の端末（空）に戻す
        let otherContainer = try ModelContainer(for: Session.self, ReflectionCard.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let other = otherContainer.mainContext
        let local = Session(mode: .device, startedAt: Date(timeIntervalSince1970: 1_700_000_000), requiredWaitSeconds: 60)
        local.phase = .completed; local.outcome = .deferred
        other.insert(local)
        func restore() -> Int {
            let ids = Set(((try? other.fetch(FetchDescriptor<Session>())) ?? []).map(\.id))
            let plan = BackupMergePlan.make(document: doc, existingSessionIDs: ids, existingCardKeys: [])
            XCTAssertTrue(BackupRestorer.apply(plan, to: other))
            return plan.newSessions.count
        }
        XCTAssertEqual(restore(), 1)
        XCTAssertEqual(restore(), 0, "2回戻しても、重複しない")
        let all = try other.fetch(FetchDescriptor<Session>())
        XCTAssertEqual(all.count, 2)
        XCTAssertTrue(all.contains { $0.id == local.id && $0.outcome == .deferred }, "もとからある記録は、変わらない")
        let restored = try XCTUnwrap(all.first { $0.id == original.id })
        XCTAssertEqual(restored.purpose, .research)
        XCTAssertEqual(restored.reflection, .satisfied)
        XCTAssertNil(restored.temporaryUnlockedApps)
        XCTAssertEqual(restored.mode, .device)
    }
}
