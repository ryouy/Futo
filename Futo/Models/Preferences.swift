import Foundation

enum NotificationKind: String, Codable, CaseIterable, Identifiable {
    case morning
    case night
    case postUse
    case outing

    var id: String { rawValue }
}

/// 設定値。UserDefaultsにJSONで1つ保存する。足りないキーは既定値になる。
struct Preferences: Codable, Equatable {
    /// nil は既定値（Releaseは3分、Debugは10秒）
    var waitSeconds: Double?

    /// 解除していられる分数（その分だけ使うと制限に戻る）。nil は既定（Releaseは5分、Debugは1分）
    var unlockMinutes: Int?

    var morningEnabled = true
    var morningMinute = 8 * 60
    var nightEnabled = true
    var nightMinute = 21 * 60

    /// 通知は、初期状態はすべてオフ
    var notifyMorning = false
    var notifyNight = false
    var notifyPostUse = false
    var notifyOuting = false
    var outingMinute = 15 * 60

    /// 静かな時間（この間は通知しない）。既定は22時〜翌8時
    var quietStartMinute = 22 * 60
    var quietEndMinute = 8 * 60

    init() {}

    #if DEBUG
    static let defaultWaitSeconds: Double = 10
    static let waitOptions: [Double] = [10, 60, 120, 180, 300, 600]
    #else
    static let defaultWaitSeconds: Double = 180
    static let waitOptions: [Double] = [60, 120, 180, 300, 600]
    #endif

    var effectiveWaitSeconds: Double { waitSeconds ?? Self.defaultWaitSeconds }

    #if DEBUG
    static let defaultUnlockMinutes = 1
    #else
    static let defaultUnlockMinutes = 5
    #endif
    static let unlockMinuteOptions = Array(1...30)

    var effectiveUnlockMinutes: Int {
        min(max(unlockMinutes ?? Self.defaultUnlockMinutes, 1), 30)
    }

    /// Device Activityの監視区間の長さ。Appleの最短は15分なので、短い設定でも16分を下回らない。
    /// 長い設定（例：30分）では、使わなくても約31分で必ず制限に戻る。
    static func unlockWindowSeconds(minutes: Int) -> TimeInterval {
        Double(max(minutes + 1, 16)) * 60
    }

    func isNotificationOn(_ kind: NotificationKind) -> Bool {
        switch kind {
        case .morning: return notifyMorning
        case .night: return notifyNight
        case .postUse: return notifyPostUse
        case .outing: return notifyOuting
        }
    }

    mutating func setNotification(_ kind: NotificationKind, _ on: Bool) {
        switch kind {
        case .morning: notifyMorning = on
        case .night: notifyNight = on
        case .postUse: notifyPostUse = on
        case .outing: notifyOuting = on
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waitSeconds = try c.decodeIfPresent(Double.self, forKey: .waitSeconds)
        unlockMinutes = try c.decodeIfPresent(Int.self, forKey: .unlockMinutes)
        morningEnabled = try c.decodeIfPresent(Bool.self, forKey: .morningEnabled) ?? true
        morningMinute = try c.decodeIfPresent(Int.self, forKey: .morningMinute) ?? 8 * 60
        nightEnabled = try c.decodeIfPresent(Bool.self, forKey: .nightEnabled) ?? true
        nightMinute = try c.decodeIfPresent(Int.self, forKey: .nightMinute) ?? 21 * 60
        notifyMorning = try c.decodeIfPresent(Bool.self, forKey: .notifyMorning) ?? false
        notifyNight = try c.decodeIfPresent(Bool.self, forKey: .notifyNight) ?? false
        notifyPostUse = try c.decodeIfPresent(Bool.self, forKey: .notifyPostUse) ?? false
        notifyOuting = try c.decodeIfPresent(Bool.self, forKey: .notifyOuting) ?? false
        outingMinute = try c.decodeIfPresent(Int.self, forKey: .outingMinute) ?? 15 * 60
        quietStartMinute = try c.decodeIfPresent(Int.self, forKey: .quietStartMinute) ?? 22 * 60
        quietEndMinute = try c.decodeIfPresent(Int.self, forKey: .quietEndMinute) ?? 8 * 60
    }
}

/// 「3分」「10秒」のような言い表し。
func durationText(seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let minutes = total / 60, rest = total % 60
    if minutes == 0 { return "\(rest)秒" }
    return rest == 0 ? "\(minutes)分" : "\(minutes)分\(rest)秒"
}

/// 0時からの分を「8:00」の形にする。
func clockText(minute: Int) -> String {
    String(format: "%d:%02d", (minute / 60) % 24, minute % 60)
}
