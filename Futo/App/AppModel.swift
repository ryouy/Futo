import Foundation
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
    var showFlow = false
    var permissionError: String?
    var notice: String?
    var errorMessage: String?

    init(context: ModelContext, defaults: UserDefaults = .standard) {
        let settings = AppSettings(defaults: defaults)
        self.settings = settings
        self.sessions = SessionStore(context: context)
        self.demo = DemoRestrictionService(defaults: defaults)
        self.device = DeviceRestrictionService(defaults: defaults)
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
        activeSession = sessions.begin(mode: mode, requiredWaitSeconds: settings.waitSeconds)
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

    func finish(_ outcome: SessionOutcome) {
        guard let session = activeSession, sessions.finish(session, outcome: outcome) else { return }
        lastResult = outcome
        activeSession = nil
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
        showFlow = false
    }

    func deleteAllRecords() {
        sessions.deleteAll()
        activeSession = nil
        showFlow = false
        lastResult = nil
    }
}
