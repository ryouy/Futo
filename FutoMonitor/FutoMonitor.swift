import DeviceActivity
import Foundation

/// 一時解除の監視。しきい値到達、または監視区間の終了で、対象アプリを再び制限する。
/// 現在の一時解除に対応するイベントだけを処理し、古い・重複したイベントは無視する。
final class FutoMonitor: DeviceActivityMonitor {
    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        handle(activity, reason: "利用が設定の分数に達した")
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        handle(activity, reason: "監視区間が終了した")
    }

    private func handle(_ activity: DeviceActivityName, reason: String) {
        // 制限全体の一時停止の区間：終わったら、停止前の制限へ戻す。
        if activity.rawValue.hasPrefix(PauseState.activityPrefix) {
            if SharedState.relockFromPause(activityName: activity.rawValue, reason: reason) {
                DeviceActivityCenter().stopMonitoring([activity])
            }
            return
        }
        guard SharedState.isCurrentUnlock(activity.rawValue) else {
            return
        }
        SharedState.relock(reason: reason)
        DeviceActivityCenter().stopMonitoring([activity])
    }
}
