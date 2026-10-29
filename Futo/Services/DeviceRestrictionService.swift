import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// 実機用。個人向けScreen Time認証と、本アプリ専用のManagedSettingsStoreによる制限。
/// 対象はアプリ単位のみ。カテゴリ・Webサイトは保存しない。
/// 一時解除は、Device Activityの監視を登録できた場合だけ行い、再制限は拡張（FutoMonitor）が担う。
@MainActor
final class DeviceRestrictionService: RestrictionService {
    enum SelectionResult: Equatable {
        case saved
        /// カテゴリやWebサイトが含まれていた。何も保存していない。
        case unsupportedItems
    }

    private let defaults: UserDefaults
    /// 本アプリ専用のストア。他のScreen Time設定やアプリの設定には触れない。
    private let managedStore = ManagedSettingsStore(named: SharedState.storeName)
    private let center = DeviceActivityCenter()

    private(set) var selection: FamilyActivitySelection
    private(set) var permission: PermissionState = .notDetermined

    init() {
        SharedState.migrateFromStandardIfNeeded()
        self.defaults = SharedState.defaults
        self.selection = SharedState.loadSelection() ?? FamilyActivitySelection()
        refreshPermission()
    }

    var targetCount: Int { selection.applicationTokens.count }
    var intendsRestriction: Bool { SharedState.intendsRestriction }

    func refreshPermission() {
        switch AuthorizationCenter.shared.authorizationStatus {
        case .approved: permission = .approved
        case .denied: permission = .denied
        case .notDetermined: permission = .notDetermined
        @unknown default: permission = .notDetermined
        }
    }

    func requestPermission() async -> String? {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            refreshPermission()
            return permission == .approved ? nil : "許可が完了しませんでした。もう一度お試しください。"
        } catch {
            refreshPermission()
            return "許可が完了しませんでした。もう一度お試しください。"
        }
    }

    /// アプリのみの選択を保存する。カテゴリ・Webサイトが含まれる場合は何も保存しない。
    func saveSelection(_ newSelection: FamilyActivitySelection) -> SelectionResult {
        guard newSelection.categoryTokens.isEmpty, newSelection.webDomainTokens.isEmpty else {
            return .unsupportedItems
        }
        selection = newSelection
        SharedState.saveSelection(newSelection)
        if newSelection.applicationTokens.isEmpty {
            SharedState.intendsRestriction = false
        }
        return .saved
    }

    func start() {
        guard permission == .approved, !selection.applicationTokens.isEmpty else { return }
        managedStore.shield.applications = selection.applicationTokens
        SharedState.intendsRestriction = true
    }

    @discardableResult
    func stop() -> Bool {
        stopUnlockMonitoring()
        SharedState.unlock = nil
        managedStore.shield.applications = nil
        SharedState.intendsRestriction = false
        return managedStore.shield.applications == nil
    }

    // MARK: 一時解除（試験機能）

    var supportsTemporaryUnlock: Bool { SharedState.isAvailable }

    /// 選んだアプリだけを一時的に使えるようにする。監視を登録できた場合だけ解除し、失敗時は制限を維持する。
    /// 選ばれなかったアプリは制限されたまま。
    func temporaryUnlock(apps: Set<ApplicationToken>) -> UnlockStartResult {
        guard SharedState.isAvailable else { return .unsupported }
        guard permission == .approved, intendsRestriction,
              !apps.isEmpty, apps.isSubset(of: selection.applicationTokens) else {
            return .failed
        }
        stopUnlockMonitoring()

        let start = Date()
        let end = start.addingTimeInterval(SharedState.unlockWindow)
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        let name = DeviceActivityName(SharedState.unlockActivityPrefix + UUID().uuidString)
        let usageEvent = DeviceActivityEvent(
            applications: apps,
            threshold: DateComponents(minute: SharedState.unlockUsageMinutes)
        )

        // 拡張が受け取るイベントを識別できるよう、記録を先に保存する。登録に失敗したら消して制限を維持する。
        SharedState.unlock = UnlockRecord(activityName: name.rawValue, startedAt: start, endsAt: end)
        do {
            try center.startMonitoring(name, during: schedule,
                                       events: [DeviceActivityEvent.Name(SharedState.usageEventName): usageEvent])
        } catch {
            SharedState.unlock = nil
            SharedState.log("監視を登録できませんでした: \(error.localizedDescription)")
            return .failed
        }
        let remaining = selection.applicationTokens.subtracting(apps)
        managedStore.shield.applications = remaining.isEmpty ? nil : remaining
        SharedState.log("一時解除を開始しました（\(apps.count)件）")
        return .started(until: end)
    }

    func relock() {
        stopUnlockMonitoring()
        SharedState.relock(reason: "アプリから制限に戻しました")
    }

    private func stopUnlockMonitoring() {
        let names = center.activities.filter { $0.rawValue.hasPrefix(SharedState.unlockActivityPrefix) }
        if !names.isEmpty { center.stopMonitoring(names) }
    }

    /// 権限・一時解除の監視・本アプリのストアを照合する。OS上でシールドが実際に出ているかまでは確認できない。
    func verify() -> RestrictionState {
        guard intendsRestriction else { return .off }
        guard permission == .approved, !selection.applicationTokens.isEmpty else { return .unverifiable }

        if let record = SharedState.unlock {
            let monitoring = center.activities.contains { $0.rawValue == record.activityName }
            if Date() < record.endsAt, monitoring {
                return .temporarilyUnlocked(until: record.endsAt)
            }
            // 拡張が再制限していない場合の安全側の補正。解除したままにしない。
            stopUnlockMonitoring()
            SharedState.relock(reason: "アプリで未再制限を検出し、再制限しました")
        }
        return managedStore.shield.applications == selection.applicationTokens ? .configured : .unverifiable
    }
}
