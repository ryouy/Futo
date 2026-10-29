import FamilyControls
import Foundation
import ManagedSettings
import Observation
import SwiftData

/// 画面から使う窓口。OS権限・制限・Sessionの操作はここを通し、Viewには持たせない。
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let sessions: SessionStore
    let demo: DemoRestrictionService
    let device: DeviceRestrictionService
    let cards: ReflectionCardStore
    let notifications = NotificationService.shared

    private(set) var mode: AppMode
    private(set) var onboardingDone: Bool
    /// Debugで初回説明を見直しているとき。モードや制限には一切触れず、閉じるだけにする
    private(set) var isOnboardingReplay = false
    /// ホームのチュートリアルの現在のステップ。nil は表示していない
    var tutorialStep: Int?
    private(set) var tutorialCompleted: Bool
    private(set) var permission: PermissionState = .notDetermined
    private(set) var restriction: RestrictionState = .off
    private(set) var targetCount = 0
    private(set) var activeSession: Session?
    /// 一時解除中のもの（実機のみ）。ホームで解除中と分かるように表示する
    private(set) var unlockedItems = RestrictedItems()

    /// 設定値（待機時間・朝夜・通知）。変更は `updatePreferences` を通す
    var prefs: Preferences
    /// ホームに出す、今日の未クローズの朝夜カード
    var visibleCards: [ReflectionCard] = []
    /// 今表示する設定改善の提案（週1回まで）
    var suggestion: Suggestion?
    var notificationMessage: String?
    /// 通知を有効にする前の説明を出している間だけ値が入る
    var pendingNotificationEnable: NotificationKind?
    @ObservationIgnored var scheduleTask: Task<Void, Never>?

    /// 最終選択の直後に表示する結果
    private(set) var lastResult: SessionOutcome?
    /// 最終選択で「使いたい」を選んだ直後の、一時解除の結果
    private(set) var unlockResult: UnlockStartResult?
    /// 「使いたい」の後、解除するものを選んでもらっている間だけ true
    private(set) var awaitingUnlockSelection = false
    /// 解除の処理中（OSへの設定に少し時間がかかるため、先に画面を切り替える）
    private(set) var isUnlocking = false
    @ObservationIgnored private var finishedSession: Session?
    var showFlow = false
    var permissionError: String?
    var notice: String?
    var errorMessage: String?

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        let settings = AppSettings(defaults: defaults)
        self.settings = settings
        self.sessions = SessionStore(context: context)
        self.cards = ReflectionCardStore(context: context)
        self.prefs = settings.preferences
        self.demo = DemoRestrictionService(defaults: defaults)
        self.device = DeviceRestrictionService()
        self.mode = settings.mode
        self.onboardingDone = settings.onboardingDone
        self.tutorialCompleted = settings.tutorialDone
        refresh()
    }

    private var service: RestrictionService {
        mode == .demo ? demo : device
    }

    var intendsRestriction: Bool { service.intendsRestriction }

    /// 対象を変えられるのは、制限がかかっていない間だけ（制限オフ、または一時解除中）。
    var isTargetEditLocked: Bool {
        if case .temporarilyUnlocked = restriction { return false }
        return service.intendsRestriction
    }

    // MARK: 状態の再確認

    /// 起動時・前面復帰時・操作後に、OSと保存済みSessionから状態を取り直す。
    func refresh() {
        service.refreshPermission()
        permission = service.permission
        if permission == .approved { permissionError = nil }
        targetCount = service.targetCount
        restriction = service.verify()
        if mode == .device, case .temporarilyUnlocked = restriction {
            unlockedItems = device.unlockedItems
        } else {
            unlockedItems = RestrictedItems()
        }
        activeSession = sessions.openSession(mode: mode)
        applyUnlockEnds()
        updateCards()
        updateSuggestion()

        // 「続ける」機能は無い。画面の外に残った進行中のひと呼吸（起動し直したときなど）は中断として閉じる。
        if let open = activeSession, !showFlow {
            sessions.interrupt(open)
            activeSession = nil
        }

        // 権限を失った実機では、進行中の振り返りを中断して案内する。
        if mode == .device, permission != .approved, let session = activeSession {
            sessions.interrupt(session)
            activeSession = nil
            showFlow = false
            notice = "許可を確認できなかったため、ひと呼吸を中断しました。"
        }
    }

    // MARK: 初回

    func completeOnboarding(mode newMode: AppMode) {
        mode = newMode
        settings.mode = newMode
        settings.onboardingDone = true
        onboardingDone = true
        refresh()
    }

    #if DEBUG
    /// 開発用：初回説明をもう一度表示する。変えるのは「説明を見た」フラグだけで、
    /// 履歴・制限の設定・動作モードは変えない。
    func replayOnboardingForDebug() {
        settings.onboardingDone = false
        onboardingDone = false
        settings.tutorialDone = false     // 説明のあとに、ホームのチュートリアルまで流す
        tutorialCompleted = false
        isOnboardingReplay = true
        showFlow = false
    }
    #endif

    /// 見直し用の説明を閉じる。モードも制限も変えない。
    func finishOnboardingReplay() {
        settings.onboardingDone = true
        onboardingDone = true
        isOnboardingReplay = false
        refresh()
    }

    // MARK: ホームのチュートリアル

    /// 説明を終えて、まだチュートリアルを見ていなければ始める。
    func startTutorialIfNeeded() {
        guard onboardingDone, !tutorialCompleted, tutorialStep == nil, !showFlow else { return }
        tutorialStep = 0
    }

    func finishTutorial() {
        tutorialStep = nil
        tutorialCompleted = true
        settings.tutorialDone = true
    }

    // MARK: モード

    /// デモ ⇄ 実機。実機の制限を有効にしたままデモへは移らない。
    @discardableResult
    func switchMode(to newMode: AppMode) -> Bool {
        guard newMode != mode else { return true }
        if mode == .device, device.intendsRestriction {
            guard device.stop() else {
                errorMessage = "実際の制限を終了できたか確認できないため、切り替えを保留しました。設定の「いつも制限する」をはずしてお試しください。"
                refresh()
                return false
            }
        }
        mode = newMode
        settings.mode = newMode
        showFlow = false
        lastResult = nil
        unlockResult = nil
        refresh()
        return true
    }

    // MARK: 権限・対象・制限

    func requestPermission() async {
        permissionError = nil
        permissionError = await service.requestPermission()
        refresh()
    }

    func selectDemoTarget(_ name: String?) {
        guard !isTargetEditLocked else { return }
        demo.selectTarget(name)
        refresh()
    }

    func didChangeDeviceSelection() {
        refresh()
    }

    /// 1つを制限から外す。デモでは唯一の対象を外す。
    func removeItem(_ item: RestrictedItem) {
        guard !isTargetEditLocked else { return }
        device.removeItem(item)
        refresh()
    }

    func removeDemoTarget() {
        guard !isTargetEditLocked else { return }
        demo.selectTarget(nil)
        refresh()
    }

    func startRestriction() {
        guard permission == .approved else {
            notice = "許可が必要です"
            return
        }
        guard targetCount > 0 else {
            notice = "制限するものを選んでください"
            return
        }
        service.start()
        refresh()
        if restriction != .configured {
            errorMessage = "設定を確認できませんでした。もう一度お試しください"
        }
    }

    func stopRestriction() {
        if !service.stop() {
            errorMessage = "制限を外せたか確認できませんでした。もう一度お試しください"
        }
        refresh()
    }

    // MARK: ひと呼吸（Session）

    func beginBreath() {
        guard activeSession != nil || restriction == .configured else { return }
        lastResult = nil
        activeSession = sessions.begin(mode: mode, requiredWaitSeconds: prefs.effectiveWaitSeconds)
        showFlow = true
    }

    func choosePurpose(_ purpose: Purpose?) {
        guard let session = activeSession else { return }
        sessions.startWaiting(session, purpose: purpose)
    }

    /// 目的選択から戻る。まだ始まっていないSessionは残さない。
    func leavePurposeStep() {
        if let session = activeSession, sessions.discardUnstarted(session) {
            activeSession = nil
        }
        showFlow = false
    }

    /// 「使いたい」は記録し、実機で対応していれば一時解除を試みる。失敗時は制限を維持する。
    func finish(_ outcome: SessionOutcome) {
        guard let session = activeSession, sessions.finish(session, outcome: outcome) else { return }
        lastResult = outcome
        activeSession = nil
        unlockResult = nil
        guard outcome == .wantsToUse, mode == .device else { return }
        if canTemporarilyUnlock {
            finishedSession = session
            awaitingUnlockSelection = true
        } else {
            unlockResult = .unsupported
        }
    }

    /// 選んだものだけを一時解除する。OSへの設定は少し時間がかかるので、先に画面を「解除しています」に切り替えてから行う。
    func unlockItems(_ items: RestrictedItems) {
        awaitingUnlockSelection = false
        isUnlocking = true
        let session = finishedSession
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            let result = device.temporaryUnlock(items: items, sessionID: session?.id, minutes: prefs.effectiveUnlockMinutes)
            unlockResult = result
            if case .started(let until) = result, let session {
                sessions.recordTemporaryUnlock(session, apps: try? JSONEncoder().encode(items))
                schedulePostUseCheck(session: session, at: until)
            }
            finishedSession = nil
            isUnlocking = false
            refresh()
        }
    }

    func answerReflection(_ session: Session, _ reflection: Reflection) {
        sessions.recordReflection(session, reflection)
        removePostUseCheck(session: session)
    }

    /// 解除せずに閉じる。制限は続く。
    func declineUnlock() {
        awaitingUnlockSelection = false
        finishedSession = nil
    }

    /// 「3分」「10秒」のような、待機時間の言い表し。
    var waitDurationText: String {
        durationText(seconds: activeSession?.requiredWaitSeconds ?? prefs.effectiveWaitSeconds)
    }

    var canTemporarilyUnlock: Bool { mode == .device && service.supportsTemporaryUnlock }

    func relockNow() {
        service.relock()
        refresh()
    }

    func endBreath() {
        if let session = activeSession {
            sessions.interrupt(session)
            activeSession = nil
        }
        showFlow = false
    }

    /// ひと呼吸の画面を閉じる。画面が消えきるまで中身を保ち、消えてから片づける（途中で文字が変わって見えないように）。
    func closeFlow() {
        showFlow = false
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !showFlow else { return }
            lastResult = nil
            unlockResult = nil
            awaitingUnlockSelection = false
            isUnlocking = false
            finishedSession = nil
        }
    }

    func deleteAllRecords() {
        sessions.deleteAll()
        cards.deleteAll()
        settings.postUseEntries = []
        visibleCards = []
        rescheduleNotifications()
        activeSession = nil
        showFlow = false
        lastResult = nil
    }
}
