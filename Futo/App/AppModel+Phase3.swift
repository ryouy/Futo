import Foundation
import UserNotifications

/// Phase 3：朝夜の振り返り、設定改善の提案、通知。
extension AppModel {
    /// 開発中は昨日の記録が無いため、朝の振り返りも今日の記録で作る。
    private var useTodayForMorning: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    // MARK: 設定

    /// 表示言語を切り替える。通知の文言も、新しい言語で予約し直す。
    func changeLanguage(_ language: AppLanguage) {
        LanguageStore.shared.select(language)
        refresh()
        rescheduleNotifications()
    }

    func updatePreferences(_ change: (inout Preferences) -> Void) {
        var updated = prefs
        change(&updated)
        guard updated != prefs else { return }
        prefs = updated
        settings.preferences = updated
        updateCards()
        rescheduleNotifications()
    }

    /// 拡張や本体が記録した「解除が終わった時刻」を、履歴のひと呼吸に反映する。
    func applyUnlockEnds() {
        let ends = SharedState.unlockEnds
        guard !ends.isEmpty else { return }
        let all = sessions.all()
        for end in ends {
            if let session = all.first(where: { $0.id == end.sessionID }) {
                sessions.recordTemporaryUnlockEnd(session, at: end.endedAt)
            }
        }
        SharedState.unlockEnds = []
    }

    // MARK: 朝夜の振り返りカード

    /// 設定した時刻の枠にいれば、今日の朝・夜のカードを（無ければ1度だけ）作る。表示するのは未クローズのものだけ。
    func updateCards(now: Date = Date()) {
        let calendar = LogicalCalendar()
        let kinds: [(ReflectionKind, Bool, Int)] = [
            (.morning, prefs.morningEnabled, prefs.morningMinute),
            (.night, prefs.nightEnabled, prefs.nightMinute),
        ]
        for (kind, enabled, minute) in kinds where enabled
            && ReflectionSchedule.isAvailable(clockMinute: minute, now: now, calendar: calendar) {
            _ = card(for: kind, now: now, regenerate: false)
        }
        let today = calendar.dayKey(for: now)
        let order: [ReflectionKind] = [.morning, .night]
        visibleCards = cards.all()
            .filter { $0.mode == mode && $0.dayKey == today && $0.dismissedAt == nil }
            .sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
    }

    private func card(for kind: ReflectionKind, now: Date, regenerate: Bool) -> ReflectionCard {
        let calendar = LogicalCalendar()
        let range = ReflectionSchedule.contentRange(kind: kind, now: now, calendar: calendar,
                                                    useTodayForMorning: useTodayForMorning)
        return cards.ensureCard(
            mode: mode, kind: kind, dayKey: calendar.dayKey(for: now),
            content: ReflectionBuilder.build(kind: kind, sessions: sessions.all(), mode: mode,
                                             interval: range.interval, dayWord: range.dayWord,
                                             seed: calendar.dayKey(for: now)),
            regenerate: regenerate)
    }

    /// 開発用：時間帯に関係なく、今の記録で朝／夜のカードをすぐ作って表示する。
    func showReflectionNow(_ kind: ReflectionKind) {
        _ = card(for: kind, now: Date(), regenerate: true)
        updateCards()
        rescheduleNotifications()
    }

    func dismissCard(_ card: ReflectionCard) {
        cards.dismiss(card)
        updateCards()
        rescheduleNotifications()
    }

    /// 通知のタップ。対象が無い・閉じ済みでも、そのままホームが見えるだけで困らない。
    func handleNotificationTap(_ kind: NotificationKind) {
        showFlow = false
        switch kind {
        case .morning: _ = card(for: .morning, now: Date(), regenerate: false)
        case .night: _ = card(for: .night, now: Date(), regenerate: false)
        case .postUse, .outing: break
        }
        refresh()
    }

    // MARK: 設定改善の提案

    func updateSuggestion(now: Date = Date()) {
        var state = settings.suggestionState
        suggestion = SuggestionEngine.evaluate(
            state: &state, sessions: sessions.all(), mode: mode, preferences: prefs,
            calendar: LogicalCalendar(), now: now)
        settings.suggestionState = state
    }

    /// 本人が確認したあとにだけ呼ぶ。設定を自動では変えない。
    func applySuggestion() {
        guard let current = suggestion else { return }
        resolveSuggestion(.changed)
        switch current.change {
        case .waitSeconds(let seconds): updatePreferences { $0.waitSeconds = seconds }
        case .nightMinute(let minute): updatePreferences { $0.nightMinute = minute }
        }
    }

    func resolveSuggestion(_ status: SuggestionStatus) {
        var state = settings.suggestionState
        SuggestionEngine.resolve(state: &state, status: status, now: Date())
        settings.suggestionState = state
        suggestion = nil
    }

    // MARK: 通知

    /// 通知をオンにする操作。初回は用途の説明を出し、本人が進めたときだけOSの許可を求める。
    func requestEnableNotification(_ kind: NotificationKind) {
        Task { @MainActor in
            switch await notifications.authorizationStatus() {
            case .authorized, .provisional, .ephemeral:
                updatePreferences { $0.setNotification(kind, true) }
            case .notDetermined:
                pendingNotificationEnable = kind
            default:
                notificationMessage = tr("通知が許可されていません。iPhoneの設定アプリで変えられます。")
            }
        }
    }

    func confirmEnableNotification() {
        guard let kind = pendingNotificationEnable else { return }
        pendingNotificationEnable = nil
        Task { @MainActor in
            if await notifications.requestAuthorization() {
                updatePreferences { $0.setNotification(kind, true) }
            } else {
                notificationMessage = tr("通知は許可されませんでした。通知なしでも、すべての機能が使えます。")
            }
        }
    }

    func disableNotification(_ kind: NotificationKind) {
        updatePreferences { $0.setNotification(kind, false) }
    }

    /// 利用後の確認通知の予定を記録する。実際に予約されるかは、上限・間隔の判定しだい。
    func schedulePostUseCheck(session: Session, at date: Date) {
        guard prefs.notifyPostUse else { return }
        var entries = settings.postUseEntries.filter { $0.sessionID != session.id }
        entries.append(PostUseEntry(sessionID: session.id, fireDate: date))
        settings.postUseEntries = entries
        rescheduleNotifications()
    }

    func removePostUseCheck(session: Session) {
        settings.postUseEntries = settings.postUseEntries.filter { $0.sessionID != session.id }
        rescheduleNotifications()
    }

    func didBecomeActive() {
        refresh()
        rescheduleNotifications()
    }

    /// 予約をまとめて組み直す（今日と明日の分のみ）。複数の機能が別々に予約しない。
    func rescheduleNotifications() {
        scheduleTask?.cancel()
        scheduleTask = Task { @MainActor in
            let status = await notifications.authorizationStatus()
            let allowed = status == .authorized || status == .provisional || status == .ephemeral
            guard allowed else {
                await notifications.replaceAll(with: [])
                return
            }
            let now = Date()
            let calendar = LogicalCalendar()
            let viewed = Set(cards.all().filter { $0.mode == mode }.map { "\($0.kind.rawValue).\($0.dayKey)" })
            var candidates = NotificationPlanner.recurring(preferences: prefs, now: now, calendar: calendar, viewed: viewed)

            // 利用後の確認：時刻を過ぎた・回答済み・対象が無いものは作らない
            let open = Dictionary(uniqueKeysWithValues: sessions.all().map { ($0.id, $0) })
            let entries = settings.postUseEntries.filter {
                $0.fireDate > now && open[$0.sessionID]?.reflection == nil && open[$0.sessionID] != nil
            }
            settings.postUseEntries = entries
            if prefs.notifyPostUse {
                candidates += entries.map {
                    NotificationCandidate(kind: .postUse, id: "futo.postUse.\($0.sessionID.uuidString)", fireDate: $0.fireDate)
                }
            }
            // 静かな時間は設けない（開始と終了を同じにして、無効にする）
            let policy = NotificationPolicy(quietStartMinute: 0, quietEndMinute: 0, calendar: .current)
            guard !Task.isCancelled else { return }
            await notifications.replaceAll(with: NotificationPlanner.select(candidates, policy: policy).accepted)
        }
    }

    /// 開発用：お出かけの通知を数秒後に1件送る（許可が無ければ、このときだけ尋ねる）。
    func sendTestNotification(_ kind: NotificationKind = .outing) {
        Task { @MainActor in
            if await notifications.authorizationStatus() == .notDetermined {
                _ = await notifications.requestAuthorization()
            }
            await notifications.sendTest(kind: kind)
        }
    }
}
