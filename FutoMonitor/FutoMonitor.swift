import DeviceActivity
import Foundation

/// 一時解除の監視。監視区間の終了（解除してから設定の時間がたった時刻）で、対象アプリを再び制限する。利用時間は使わない。
/// 現在の一時解除に対応するイベントだけを処理し、古い・重複したイベントは無視する。
final class FutoMonitor: DeviceActivityMonitor {
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
