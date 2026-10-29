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

    private(set) var mode: AppMode
    private(set) var onboardingDone: Bool
    private(set) var permission: PermissionState = .notDetermined
    private(set) var restriction: RestrictionState = .off
    private(set) var targetCount = 0
    private(set) var activeSession: Session?

    /// 最終選択の直後に表示する結果
    private(set) var lastResult: SessionOutcome?
    /// 最終選択で「使いたい」を選んだ直後の、一時解除の結果
    private(set) var unlockResult: UnlockStartResult?
    /// 「使いたい」の後、解除するアプリを選んでもらっている間だけ true
    private(set) var awaitingUnlockSelection = false
    @ObservationIgnored private var finishedSession: Session?
    var showFlow = false
    var permissionError: String?
    var notice: String?
    var errorMessage: String?

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        let settings = AppSettings(defaults: defaults)
        self.settings = settings
        self.sessions = SessionStore(context: context)
        self.demo = DemoRestrictionService(defaults: defaults)
        self.device = DeviceRestrictionService()
        self.mode = settings.mode
        self.onboardingDone = settings.onboardingDone
        refresh()
    }

    private var service: RestrictionService {
        mode == .demo ? demo : device
    }

    var intendsRestriction: Bool { service.intendsRestriction }

    /// 対象変更を許さない状態（制限中、または待機中）
    var isTargetLocked: Bool {
        service.intendsRestriction || (activeSession?.phase == .waiting)
    }

    // MARK: 状態の再確認

    /// 起動時・前面復帰時・操作後に、OSと保存済みSessionから状態を取り直す。
    func refresh() {
        service.refreshPermission()
        permission = service.permission
        if permission == .approved { permissionError = nil }
        targetCount = service.targetCount
        restriction = service.verify()
        activeSession = sessions.openSession(mode: mode)

        // 権限を失った実機では、進行中の振り返りを中断して案内する。
        if mode == .device, permission != .approved, let session = activeSession {
            sessions.interrupt(session)
            activeSession = nil
            showFlow = false
            notice = "アクセスの許可を確認できなかったため、進行中のひと呼吸を中断しました。"
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

    // MARK: モード

    /// デモ ⇄ 実機。実機の制限を有効にしたままデモへは移らない。
    @discardableResult
    func switchMode(to newMode: AppMode) -> Bool {
        guard newMode != mode else { return true }
        if mode == .device, device.intendsRestriction {
            guard device.stop() else {
                errorMessage = "実際の制限を終了できたか確認できないため、切り替えを保留しました。ホームの「制限を終了」をお試しください。"
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
        demo.selectTarget(name)
        refresh()
    }

    func didChangeDeviceSelection() {
        refresh()
    }

    func startRestriction() {
        guard permission == .approved else {
            notice = "制限にはアクセスの許可が必要です"
            return
        }
        guard targetCount > 0 else {
            notice = "制限したいアプリを選んでください"
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
        activeSession = sessions.begin(mode: mode, requiredWaitSeconds: AppSettings.waitSeconds)
        showFlow = true
    }

    func resumeBreath() {
        guard activeSession != nil else { return }
        lastResult = nil
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

    /// 選んだアプリだけを一時解除する。
    func unlockApps(_ apps: Set<ApplicationToken>) {
        awaitingUnlockSelection = false
        let result = device.temporaryUnlock(apps: apps)
        unlockResult = result
        if case .started = result, let session = finishedSession { sessions.recordTemporaryUnlock(session) }
        finishedSession = nil
        refresh()
    }

    /// 解除せずに閉じる。制限は続く。
    func declineUnlock() {
        awaitingUnlockSelection = false
        finishedSession = nil
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

    func closeFlow() {
        lastResult = nil
        unlockResult = nil
        awaitingUnlockSelection = false
        finishedSession = nil
        showFlow = false
    }

    func deleteAllRecords() {
        sessions.deleteAll()
        activeSession = nil
        showFlow = false
        lastResult = nil
    }
}
