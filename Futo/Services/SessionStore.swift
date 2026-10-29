import Foundation
import SwiftData

/// Sessionの保存と状態遷移。遷移ごとに現在のphaseを確認し、連打・二重呼び出しでは何も起きない。
@MainActor
final class SessionStore {
    let context: ModelContext
    private let now: () -> Date

    init(context: ModelContext, now: @escaping () -> Date = Date.init) {
        self.context = context
        self.now = now
    }

    func all() -> [Session] {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    func openSession(mode: AppMode) -> Session? {
        all().first { $0.mode == mode && $0.phase.isOpen }
    }

    /// 進行中のSessionがあればそれを返す（新規作成しない）。
    @discardableResult
    func begin(mode: AppMode, requiredWaitSeconds: Double) -> Session {
        if let open = openSession(mode: mode) { return open }
        let session = Session(mode: mode, startedAt: now(), requiredWaitSeconds: requiredWaitSeconds)
        context.insert(session)
        save()
        return session
    }

    /// 目的を確定して待機へ進む。nil は「答えずに進む」。待機時間は同じ。
    @discardableResult
    func startWaiting(_ session: Session, purpose: Purpose?) -> Bool {
        guard session.phase == .choosingPurpose else { return false }
        session.purpose = purpose
        session.remainingWaitSeconds = session.requiredWaitSeconds
        session.phase = .waiting
        save()
        return true
    }

    func saveRemaining(_ session: Session, seconds: Double) {
        guard session.phase == .waiting else { return }
        session.remainingWaitSeconds = min(max(0, seconds), session.requiredWaitSeconds)
        save()
    }

    @discardableResult
    func markWaitFinished(_ session: Session) -> Bool {
        guard session.phase == .waiting else { return false }
        session.remainingWaitSeconds = 0
        session.phase = .awaitingChoice
        save()
        return true
    }

    /// 最終選択。待機完了前、または2回目以降は何もしない。
    @discardableResult
    func finish(_ session: Session, outcome: SessionOutcome) -> Bool {
        guard session.phase == .awaitingChoice, outcome != .interrupted else { return false }
        session.outcome = outcome
        session.phase = .completed
        session.completedAt = now()
        save()
        return true
    }

    func recordTemporaryUnlock(_ session: Session) {
        guard session.phase == .completed, session.outcome == .wantsToUse,
              session.temporaryUnlockStartedAt == nil else { return }
        session.temporaryUnlockStartedAt = now()
        save()
    }

    @discardableResult
    func interrupt(_ session: Session) -> Bool {
        guard session.phase.isOpen else { return false }
        session.outcome = .interrupted
        session.phase = .interrupted
        session.completedAt = now()
        save()
        return true
    }

    /// 目的選択画面から戻った場合。まだ何も始まっていないSessionだけ破棄する。
    @discardableResult
    func discardUnstarted(_ session: Session) -> Bool {
        guard session.phase == .choosingPurpose else { return false }
        context.delete(session)
        save()
        return true
    }

    /// 進行中を中断扱いで閉じてから全件削除する。
    func deleteAll() {
        for session in all() {
            if session.phase.isOpen { _ = interrupt(session) }
            context.delete(session)
        }
        save()
    }

    private func save() {
        try? context.save()
    }
}

enum DailyCounts {
    struct Result: Equatable {
        var deferred = 0
        var wantsToUse = 0
    }

    /// 現地カレンダーの「今日」に完了した、指定モードのSessionだけを数える。
    static func today(sessions: [Session], mode: AppMode, calendar: Calendar = .current, now: Date = Date()) -> Result {
        var result = Result()
        for session in sessions where session.mode == mode {
            guard let completedAt = session.completedAt, calendar.isDate(completedAt, inSameDayAs: now) else { continue }
            switch session.outcome {
            case .deferred: result.deferred += 1
            case .wantsToUse: result.wantsToUse += 1
            default: break
            }
        }
        return result
    }
}
