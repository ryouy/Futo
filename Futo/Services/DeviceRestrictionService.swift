import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// 実機用。個人向けScreen Time認証と、本アプリ専用のManagedSettingsStoreによる制限。
/// 制限できるのは、アプリ・カテゴリ・ウェブサイト。
/// 一時解除は、Device Activityの監視を登録できた場合だけ行い、再制限は拡張（FutoMonitor）が担う。
@MainActor
final class DeviceRestrictionService: RestrictionService {
    private let center = DeviceActivityCenter()

    private(set) var selection: FamilyActivitySelection
    private(set) var permission: PermissionState = .notDetermined

    init() {
        SharedState.migrateFromStandardIfNeeded()
        self.selection = SharedState.loadSelection() ?? FamilyActivitySelection()
        refreshPermission()
    }

    /// 制限するもの（アプリ・カテゴリ・ウェブサイト）
    var items: RestrictedItems { RestrictedItems(selection: selection) }
    var targetCount: Int { items.count }
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

    /// 選んだものを保存する。制限中・一時解除中なら、ストアへもすぐ反映する。
    func saveSelection(_ newSelection: FamilyActivitySelection) {
        selection = newSelection
        SharedState.saveSelection(newSelection)
        syncShield()
    }

    /// 1つを制限の対象から外す。制限中なら、そのシールドもすぐ外れる。
    func removeItem(_ item: RestrictedItem) {
        var current = items
        guard current.contains(item) else { return }
        current.remove(item)
        selection = current.selection
        SharedState.saveSelection(selection)
        syncShield()
    }

    func start() {
        guard permission == .approved, !items.isEmpty else { return }
        SharedState.applyShield(items: items)
        SharedState.intendsRestriction = true
    }

    @discardableResult
    func stop() -> Bool {
        stopUnlockMonitoring()
        SharedState.clearUnlock()
        SharedState.clearShield()
        SharedState.intendsRestriction = false
        return SharedState.isShieldEmpty
    }

    /// 対象の変更を、制限中の本アプリ専用ストアへ反映する。対象が空になれば制限をオフにする。
    /// 変更できるのは制限オフまたは一時解除中だけ（呼び出し側で止める）。
    private func syncShield() {
        guard intendsRestriction, permission == .approved else { return }
        let current = items
        if current.isEmpty {
            stopUnlockMonitoring()
            SharedState.clearUnlock()
            SharedState.clearShield()
            SharedState.intendsRestriction = false
        } else if var record = SharedState.unlock {
            // 一時解除中の変更：解除中のものは開けたまま、追加したものは制限する。
            let stillUnlocked = (record.unlocked ?? RestrictedItems()).intersection(current)
            record.unlocked = stillUnlocked
            SharedState.unlock = record
            SharedState.applyShield(items: current, unlocked: stillUnlocked)
        } else {
            SharedState.applyShield(items: current)
        }
    }

    // MARK: 一時解除（試験機能）

    var supportsTemporaryUnlock: Bool { SharedState.isAvailable }

    /// 解除中のもの。一時解除中でなければ空。
    var unlockedItems: RestrictedItems { SharedState.unlock?.unlocked ?? RestrictedItems() }

    /// 選んだものだけを一時的に使えるようにする。監視を登録できた場合だけ解除し、失敗時は制限を維持する。
    /// 選ばれなかったものは制限されたまま。
    func temporaryUnlock(items unlockItems: RestrictedItems, sessionID: UUID? = nil, minutes: Int) -> UnlockStartResult {
        guard SharedState.isAvailable else { return .unsupported }
        guard permission == .approved, intendsRestriction,
              !unlockItems.isEmpty, unlockItems.isSubset(of: items) else {
            return .failed
        }
        stopUnlockMonitoring()

        let start = Date()
        let end = start.addingTimeInterval(Preferences.unlockWindowSeconds(minutes: minutes))
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        let name = DeviceActivityName(SharedState.unlockActivityPrefix + UUID().uuidString)
        let usageEvent = DeviceActivityEvent(
            applications: unlockItems.apps,
            categories: unlockItems.categories,
            webDomains: unlockItems.webDomains,
            threshold: DateComponents(minute: minutes)
        )

        // 拡張が受け取るイベントを識別できるよう、記録を先に保存する。登録に失敗したら消して制限を維持する。
        SharedState.unlock = UnlockRecord(activityName: name.rawValue, startedAt: start, endsAt: end,
                                          unlocked: unlockItems, sessionID: sessionID, minutes: minutes)
        do {
            try center.startMonitoring(name, during: schedule,
                                       events: [DeviceActivityEvent.Name(SharedState.usageEventName): usageEvent])
        } catch {
            SharedState.unlock = nil
            SharedState.log("監視を登録できませんでした: \(error.localizedDescription)")
            return .failed
        }
        SharedState.applyShield(items: items, unlocked: unlockItems)
        SharedState.log("一時解除を開始しました（\(unlockItems.count)件）")
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
        guard permission == .approved, !items.isEmpty else { return .unverifiable }

        if let record = SharedState.unlock {
            let monitoring = center.activities.contains { $0.rawValue == record.activityName }
            if Date() < record.endsAt, monitoring {
                return .temporarilyUnlocked(until: record.endsAt)
            }
            // 拡張が再制限していない場合の安全側の補正。解除したままにしない。
            stopUnlockMonitoring()
            SharedState.relock(reason: "アプリで未再制限を検出し、再制限しました")
        }
        return SharedState.shieldMatches(items: items) ? .configured : .unverifiable
    }
}
