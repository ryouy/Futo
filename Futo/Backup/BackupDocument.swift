import Foundation
import SwiftData

/// Google Driveのアプリ専用領域に置くバックアップの中身（JSON、1ファイル）。
///
/// 入れるもの：実機の、終わったひと呼吸の記録、朝夜の振り返りカード、設定値、テーマ・言語。
/// 入れないもの（移さない）：Screen Timeの許可・制限の対象（OSのトークン）、進行中の一時解除、通知の許可、
/// ログインのトークン、デモモードの記録、途中のひと呼吸。移したあとは、制限の対象と通知の許可を、設定し直す。
struct BackupDocument: Codable, Equatable {
    static let currentVersion = 1
    static let fileName = "futo-backup.json"

    struct SessionRecord: Codable, Equatable {
        var id: UUID
        var startedAt: Date
        var purpose: Purpose?
        var requiredWaitSeconds: Double
        var phase: SessionPhase
        var outcome: SessionOutcome?
        var completedAt: Date?
        var temporaryUnlockStartedAt: Date?
        var temporaryUnlockEndedAt: Date?
        var reflection: Reflection?
    }

    struct EventRecord: Codable, Equatable {
        var id: UUID
        var kind: RestrictionEventKind
        var at: Date
        var minutes: Int?
    }

    struct CardRecord: Codable, Equatable {
        var key: String
        var kind: ReflectionKind
        var dayKey: String
        var title: String
        var body: String
        var createdAt: Date
        var dismissedAt: Date?
    }

    var schemaVersion: Int
    var createdAt: Date
    var sessions: [SessionRecord]
    var cards: [CardRecord]
    /// 制限の一時停止・終了の記録（古いバックアップには無い）
    var restrictionEvents: [EventRecord]? = nil
    var preferences: Preferences
    var theme: String?
    var language: String?

    static func make(sessions: [Session], cards: [ReflectionCard], preferences: Preferences,
                     theme: String?, language: String?, now: Date = Date(), events: [RestrictionEvent] = []) -> BackupDocument {
        let records: [SessionRecord] = sessions
            .filter { $0.mode == .device && !$0.phase.isOpen }
            .sorted { $0.startedAt < $1.startedAt }
            .map { s in
                SessionRecord(id: s.id, startedAt: s.startedAt, purpose: s.purpose, requiredWaitSeconds: s.requiredWaitSeconds,
                              phase: s.phase, outcome: s.outcome, completedAt: s.completedAt,
                              temporaryUnlockStartedAt: s.temporaryUnlockStartedAt, temporaryUnlockEndedAt: s.temporaryUnlockEndedAt,
                              reflection: s.reflection)
            }
        let cardRecords: [CardRecord] = cards
            .filter { $0.mode == .device }
            .sorted { $0.createdAt < $1.createdAt }
            .map { CardRecord(key: $0.key, kind: $0.kind, dayKey: $0.dayKey, title: $0.title, body: $0.body, createdAt: $0.createdAt, dismissedAt: $0.dismissedAt) }
        let eventRecords: [EventRecord] = events.filter { $0.mode == .device }.sorted { $0.at < $1.at }
            .map { EventRecord(id: $0.id, kind: $0.kind, at: $0.at, minutes: $0.minutes) }
        return BackupDocument(schemaVersion: currentVersion, createdAt: now, sessions: records, cards: cardRecords,
                              restrictionEvents: eventRecords, preferences: preferences, theme: theme, language: language)
    }

    // MARK: 符号化

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func encoded() throws -> Data { try Self.encoder.encode(self) }

    enum ParseError: Error, Equatable {
        case tooLarge
        case invalid
        /// このアプリより新しい形式。アプリを更新してから戻す
        case newerVersion
    }

    /// 取り込み前の検証。壊れている・大きすぎる・新しすぎるものは、何も変えずに拒否する。
    static let maxBytes = 20 * 1024 * 1024
    static let maxSessions = 100_000

    static func parse(_ data: Data) throws -> BackupDocument {
        guard data.count <= maxBytes else { throw ParseError.tooLarge }
        guard let doc = try? decoder.decode(BackupDocument.self, from: data) else {
            // 形式の版だけ読めるなら、新しい版かどうかを区別する
            struct VersionProbe: Decodable { var schemaVersion: Int }
            if let probe = try? JSONDecoder().decode(VersionProbe.self, from: data), probe.schemaVersion > currentVersion {
                throw ParseError.newerVersion
            }
            throw ParseError.invalid
        }
        guard doc.schemaVersion >= 1 else { throw ParseError.invalid }
        guard doc.schemaVersion <= currentVersion else { throw ParseError.newerVersion }
        guard doc.sessions.count <= maxSessions, doc.cards.count <= maxSessions else { throw ParseError.tooLarge }
        return doc
    }
}

/// 戻すときの取り込み計画。既存の記録は、消さない・上書きしない（同じIDは、すでにあるものを優先する）。
struct BackupMergePlan: Equatable {
    var newSessions: [BackupDocument.SessionRecord]
    var newCards: [BackupDocument.CardRecord]
    var newEvents: [BackupDocument.EventRecord] = []
    /// すでに端末にあって、取り込まなかった件数
    var skippedSessions: Int

    static func make(document: BackupDocument, existingSessionIDs: Set<UUID>, existingCardKeys: Set<String>, existingEventIDs: Set<UUID> = []) -> BackupMergePlan {
        var seen = existingSessionIDs
        var sessions: [BackupDocument.SessionRecord] = []
        var skipped = 0
        for record in document.sessions {
            // 終わっていない・値が不正なものは取り込まない
            guard !record.phase.isOpen, record.requiredWaitSeconds >= 0, record.requiredWaitSeconds <= 86_400 else { continue }
            if seen.contains(record.id) { skipped += 1; continue }
            seen.insert(record.id)
            sessions.append(record)
        }
        var keys = existingCardKeys
        var cards: [BackupDocument.CardRecord] = []
        for card in document.cards where card.key.hasPrefix("\(AppMode.device.rawValue)|") {
            if keys.contains(card.key) { continue }
            keys.insert(card.key)
            cards.append(card)
        }
        var eventIDs = existingEventIDs
        var events: [BackupDocument.EventRecord] = []
        for event in document.restrictionEvents ?? [] where !eventIDs.contains(event.id) {
            eventIDs.insert(event.id)
            events.append(event)
        }
        return BackupMergePlan(newSessions: sessions, newCards: cards, newEvents: events, skippedSessions: skipped)
    }
}

/// 取り込み。SwiftDataへ追加するだけで、既存の記録は変更しない。
enum BackupRestorer {
    @MainActor
    @discardableResult
    static func apply(_ plan: BackupMergePlan, to context: ModelContext) -> Bool {
        for record in plan.newSessions {
            let session = Session(mode: .device, startedAt: record.startedAt, requiredWaitSeconds: record.requiredWaitSeconds)
            session.id = record.id
            session.purpose = record.purpose
            session.remainingWaitSeconds = 0
            session.phase = record.phase
            session.outcome = record.outcome
            session.completedAt = record.completedAt
            session.temporaryUnlockStartedAt = record.temporaryUnlockStartedAt
            session.temporaryUnlockEndedAt = record.temporaryUnlockEndedAt
            session.reflection = record.reflection
            context.insert(session)
        }
        for card in plan.newCards {
            let model = ReflectionCard(mode: .device, kind: card.kind, dayKey: card.dayKey, title: card.title,
                                       lines: card.body.split(separator: "\n").map(String.init), createdAt: card.createdAt)
            model.key = card.key
            model.dismissedAt = card.dismissedAt
            context.insert(model)
        }
        for event in plan.newEvents {
            let model = RestrictionEvent(mode: .device, kind: event.kind, at: event.at, minutes: event.minutes)
            model.id = event.id
            context.insert(model)
        }
        do { try context.save(); return true } catch { return false }
    }
}
