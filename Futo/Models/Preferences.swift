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

    /// ゆるめる変更（待機を短く・解除を長く）は、押してから1分たつまで反映しない。待っている変更と、押した時刻。
    var pendingWaitSeconds: Double?
    var pendingWaitAt: Date?
    var pendingUnlockMinutes: Int?
    var pendingUnlockAt: Date?

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
    /// お出かけのおすすめの、1日の回数（時刻は、ランダムに、できるだけ均等に決まる）
    var outingPerDay = 1

    /// 静かな時間（この間は通知しない）。既定は22時〜翌8時
    var quietStartMinute = 22 * 60
    var quietEndMinute = 8 * 60

    init() {}

    /// 待機時間の選択肢（10秒・30秒・1分・5分・10分）。
    static let waitOptions: [Double] = [10, 30, 60, 300, 600]
    /// 解除する時間の選択肢（分）。
    static let unlockMinuteOptions: [Int] = [1, 5, 10]

    #if DEBUG || FUTO_DEMO
    static let defaultWaitSeconds: Double = 10
    static let defaultUnlockMinutes = 1
    #else
    static let defaultWaitSeconds: Double = 60
    static let defaultUnlockMinutes = 5
    #endif

    /// 以前の版で保存した、選択肢にない値は、いちばん近い選択肢に寄せる。
    private static func nearest<T: BinaryFloatingPoint>(_ value: T, in options: [T]) -> T {
        options.min { abs($0 - value) < abs($1 - value) } ?? value
    }

    /// ゆるめる変更が反映されるまでの時間（秒）
    static let loosenDelay: TimeInterval = 60

    private func isDue(_ at: Date?, now: Date) -> Bool {
        guard let at else { return false }
        return now.timeIntervalSince(at) >= Self.loosenDelay
    }

    func effectiveWaitSeconds(now: Date) -> Double {
        let value = (isDue(pendingWaitAt, now: now) ? pendingWaitSeconds : nil) ?? waitSeconds ?? Self.defaultWaitSeconds
        return Self.nearest(value, in: Self.waitOptions)
    }

    func effectiveUnlockMinutes(now: Date) -> Int {
        let value = (isDue(pendingUnlockAt, now: now) ? pendingUnlockMinutes : nil) ?? unlockMinutes ?? Self.defaultUnlockMinutes
        return Int(Self.nearest(Double(value), in: Self.unlockMinuteOptions.map(Double.init)))
    }

    var effectiveWaitSeconds: Double { effectiveWaitSeconds(now: Date()) }
    var effectiveUnlockMinutes: Int { effectiveUnlockMinutes(now: Date()) }

    /// 1分たった、待っていた変更を、本設定に移す。
    mutating func settlePending(now: Date = Date()) {
        if isDue(pendingWaitAt, now: now), let value = pendingWaitSeconds { waitSeconds = value }
        if isDue(pendingWaitAt, now: now) { pendingWaitSeconds = nil; pendingWaitAt = nil }
        if isDue(pendingUnlockAt, now: now), let value = pendingUnlockMinutes { unlockMinutes = value }
        if isDue(pendingUnlockAt, now: now) { pendingUnlockMinutes = nil; pendingUnlockAt = nil }
    }

    /// 待機時間を変える。短くする（ゆるめる）ときは1分後、長くする・同じにするときはすぐ。
    mutating func setWait(_ value: Double, now: Date = Date()) {
        settlePending(now: now)
        if value < effectiveWaitSeconds(now: now) {
            if pendingWaitSeconds != value { pendingWaitSeconds = value; pendingWaitAt = now }
        } else {
            waitSeconds = value
            pendingWaitSeconds = nil; pendingWaitAt = nil
        }
    }

    /// 解除する時間を変える。長くする（ゆるめる）ときは1分後、短くする・同じにするときはすぐ。
    mutating func setUnlockMinutes(_ value: Int, now: Date = Date()) {
        settlePending(now: now)
        if value > effectiveUnlockMinutes(now: now) {
            if pendingUnlockMinutes != value { pendingUnlockMinutes = value; pendingUnlockAt = now }
        } else {
            unlockMinutes = value
            pendingUnlockMinutes = nil; pendingUnlockAt = nil
        }
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
        pendingWaitSeconds = try c.decodeIfPresent(Double.self, forKey: .pendingWaitSeconds)
        pendingWaitAt = try c.decodeIfPresent(Date.self, forKey: .pendingWaitAt)
        pendingUnlockMinutes = try c.decodeIfPresent(Int.self, forKey: .pendingUnlockMinutes)
        pendingUnlockAt = try c.decodeIfPresent(Date.self, forKey: .pendingUnlockAt)
        // 朝夜の振り返りカードは、つねに表示する（設定で切らない）
        morningEnabled = true
        morningMinute = try c.decodeIfPresent(Int.self, forKey: .morningMinute) ?? 8 * 60
        nightEnabled = true
        nightMinute = try c.decodeIfPresent(Int.self, forKey: .nightMinute) ?? 21 * 60
        notifyMorning = try c.decodeIfPresent(Bool.self, forKey: .notifyMorning) ?? false
        notifyNight = try c.decodeIfPresent(Bool.self, forKey: .notifyNight) ?? false
        notifyPostUse = try c.decodeIfPresent(Bool.self, forKey: .notifyPostUse) ?? false
        notifyOuting = try c.decodeIfPresent(Bool.self, forKey: .notifyOuting) ?? false
        outingMinute = try c.decodeIfPresent(Int.self, forKey: .outingMinute) ?? 15 * 60
        outingPerDay = min(max(try c.decodeIfPresent(Int.self, forKey: .outingPerDay) ?? 1, 1), 6)
        quietStartMinute = try c.decodeIfPresent(Int.self, forKey: .quietStartMinute) ?? 22 * 60
        quietEndMinute = try c.decodeIfPresent(Int.self, forKey: .quietEndMinute) ?? 8 * 60
    }
}

/// 「3分」「10秒」のような言い表し。
func durationText(seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let minutes = total / 60, rest = total % 60
    if minutes == 0 { return tr("{0}秒", "\(rest)") }
    return rest == 0 ? tr("{0}分", "\(minutes)") : tr("{0}分{1}秒", "\(minutes)", "\(rest)")
}

/// 0時からの分を「8:00」の形にする。
func clockText(minute: Int) -> String {
    String(format: "%d:%02d", (minute / 60) % 24, minute % 60)
}

/// 待機のカウントダウンの表示。1分未満は、秒の数だけ（10秒なら「10」から始まる）。1分以上は「1:30」の形。
func countdownText(_ remaining: TimeInterval) -> String {
    let total = max(0, Int(remaining.rounded(.up)))
    if total < 60 { return "\(total)" }
    return String(format: "%d:%02d", total / 60, total % 60)
}
