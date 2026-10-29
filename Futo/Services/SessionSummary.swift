import Foundation

/// 履歴・今日の詳細に出す、1件ぶんの分かりやすい言い方。
extension Session {
    /// 結果の見出し。「使いたい」「中断」のような曖昧な言葉を避け、何が起きたかで言う。
    var resultTitle: String {
        switch outcome {
        case .deferred: return tr("やめた")
        case .wantsToUse: return temporaryUnlockStartedAt != nil ? tr("解除した") : tr("使いたいと答えた")
        case .interrupted, nil: return tr("途中でやめた")
        }
    }

    /// 制限を解除していた時間。解除中、または解除していなければ nil。
    /// 「使った時間」ではなく、「解除していた時間」。
    var unlockDuration: TimeInterval? {
        guard let started = temporaryUnlockStartedAt, let ended = temporaryUnlockEndedAt else { return nil }
        return max(0, ended.timeIntervalSince(started))
    }

    var isUnlockInProgress: Bool {
        temporaryUnlockStartedAt != nil && temporaryUnlockEndedAt == nil
    }

    /// 「解除 約3分」「解除 1分未満」「解除中」。解除していなければ nil。
    var unlockDurationText: String? {
        guard temporaryUnlockStartedAt != nil else { return nil }
        guard let duration = unlockDuration else { return tr("解除中") }
        if duration < 60 { return tr("解除 1分未満") }
        return tr("解除 約{0}分", "\(Int((duration / 60).rounded()))")
    }

    var purposeText: String {
        guard let purpose else { return tr("目的：答えなかった") }
        return tr("目的：{0}", "\(purpose.label)")
    }
}

/// 期間内の目的・感想の内訳（円グラフ用）。
struct Breakdown: Equatable {
    var purposes: [Slice]
    var reflections: [Slice]
    /// 「答えない」を除いた感想の回答数
    var answeredReflections: Int { reflections.reduce(0) { $0 + $1.count } }
    var answeredPurposes: Int { purposes.filter { $0.label != Breakdown.noAnswer }.reduce(0) { $0 + $1.count } }

    struct Slice: Equatable, Identifiable {
        var label: String
        var count: Int
        var id: String { label }
    }

    static var noAnswer: String { tr("答えなかった") }

    static func make(sessions: [Session], mode: AppMode, interval: DateInterval?) -> Breakdown {
        let records = PeriodInsights.records(sessions: sessions, mode: mode, interval: interval)
        var purposes = Purpose.allCases.map { p in Slice(label: p.label, count: records.filter { $0.purpose == p }.count) }
        purposes.append(Slice(label: noAnswer, count: records.filter { $0.purpose == nil }.count))
        let kinds: [Reflection] = [.satisfied, .neutral, .wishedLess]
        let reflections = kinds.map { r in Slice(label: r.label, count: records.filter { $0.reflection == r }.count) }
        return Breakdown(purposes: purposes, reflections: reflections)
    }
}
