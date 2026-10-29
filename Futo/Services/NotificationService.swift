import Foundation
import UserNotifications

/// ローカル通知のOS側の窓口。予約はすべて `NotificationPlanner` を通した結果だけを受け取る。
/// 音もバッジも使わず、ロック画面にはアプリ名や利用内容を出さない定型文だけを出す。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()
    static let identifierPrefix = "futo."

    /// 通知をタップしたときの移動先。呼び出し側がメインで処理する。
    @MainActor var onRoute: ((NotificationKind) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    func attach() {
        center.delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// 本人が通知を有効にしたときだけ呼ぶ。音・バッジは求めない。
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert])) ?? false
    }

    static func body(for kind: NotificationKind) -> String {
        switch kind {
        case .morning: return "今日のはじまりに、記録を少し見てみませんか。"
        case .night: return "一日の終わりに、少しだけ振り返りませんか。"
        case .postUse: return "使ったあとの気持ちを、よければ残せます。"
        case .outing: return "外に出て、少し歩いてみませんか。"
        }
    }

    /// 本アプリの予約済み通知をすべて外し、選ばれた候補だけを予約し直す。
    func replaceAll(with candidates: [NotificationCandidate]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        for candidate in candidates {
            let content = UNMutableNotificationContent()
            content.title = "ふと"
            content.body = Self.body(for: candidate.kind)
            content.interruptionLevel = .active   // 音・バッジは付けないが、バナーは出す（passive だと画面に出ない）
            content.userInfo = ["kind": candidate.kind.rawValue]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: candidate.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: candidate.id, content: content, trigger: trigger))
        }
    }

    /// 開発用：上限・間隔の対象外で、数秒後に1件だけ送る。
    func sendTest(kind: NotificationKind) async {
        let content = UNMutableNotificationContent()
        content.title = "ふと"
        content.body = Self.body(for: kind)
        content.interruptionLevel = .active
        content.userInfo = ["kind": kind.rawValue]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "debug.test.\(UUID().uuidString)", content: content, trigger: trigger))
    }

    /// 診断用：許可状態と、予約中の通知。
    func diagnostics() async -> (status: String, pending: [String]) {
        let settings = await center.notificationSettings()
        let status: String
        switch settings.authorizationStatus {
        case .notDetermined: status = "未確認"
        case .denied: status = "許可されていません"
        case .authorized: status = "許可済み"
        case .provisional: status = "仮の許可"
        case .ephemeral: status = "一時的な許可"
        @unknown default: status = "不明"
        }
        let requests = await center.pendingNotificationRequests()
        let lines: [String] = requests.compactMap { request in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            let kind = request.content.userInfo["kind"] as? String ?? "?"
            return "\(date.formatted(date: .abbreviated, time: .shortened))  \(kind)"
        }
        return (status, lines.sorted())
    }

    // MARK: UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let raw = response.notification.request.content.userInfo["kind"] as? String ?? ""
        guard let kind = NotificationKind(rawValue: raw) else { return }
        await MainActor.run { onRoute?(kind) }
    }
}
