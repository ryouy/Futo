import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// 一時停止の状態を、App Group（本体と拡張で共有）に保存する。
final class DevicePauseStore: PauseStoring {
    var state: PauseState? {
        get { SharedState.pauseState }
        set { SharedState.pauseState = newValue }
    }
}

/// 一時停止の区間の終わりを、Device Activityに登録する。区間が終わると、拡張（FutoMonitor）が再制限する。
/// アプリのタイマーや通知には頼らない。OSが拡張を呼ぶ時刻は、厳密には保証されない。
final class DevicePauseScheduler: PauseScheduling {
    private let center = DeviceActivityCenter()

    func isMonitoring(_ name: String) -> Bool {
        center.activities.contains { $0.rawValue == name }
    }

    func startWindow(name: String, from start: Date, to end: Date) throws {
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        try center.startMonitoring(DeviceActivityName(name), during: schedule)
    }

    func stopWindows(keeping keep: String?) {
        let names = center.activities.filter { $0.rawValue.hasPrefix(PauseState.activityPrefix) && $0.rawValue != keep }
        if !names.isEmpty { center.stopMonitoring(names) }
    }
}

/// 本アプリ専用のストア（ManagedSettings）の操作。
final class DevicePauseShield: PauseShielding {
    private let center = DeviceActivityCenter()

    func currentItemsData() -> Data? {
        guard SharedState.intendsRestriction, let selection = SharedState.loadSelection() else { return nil }
        let items = RestrictedItems(selection: selection)
        guard !items.isEmpty else { return nil }
        return try? JSONEncoder().encode(items)
    }

    func endOrdinaryUnlock() {
        let names = center.activities.filter { $0.rawValue.hasPrefix(SharedState.unlockActivityPrefix) }
        if !names.isEmpty { center.stopMonitoring(names) }
        SharedState.clearUnlock()
    }

    func relaxAll() -> Bool {
        SharedState.clearShield()
        return SharedState.isShieldEmpty
    }

    func restore(itemsData: Data) {
        guard let items = try? JSONDecoder().decode(RestrictedItems.self, from: itemsData), !items.isEmpty else { return }
        SharedState.applyShield(items: items)
    }
}
