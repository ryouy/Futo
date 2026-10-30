import Foundation
import ManagedSettings

/// 解除した対象（アプリ・カテゴリ・ウェブサイト）の名前を、OSのAPIから読み取る。
/// 記録には名前を保存していない（OSが発行する不透明なトークンだけ）ので、共有するときに、その場で読み取る。
/// 読み取れるかどうかはOSと許可の状態に依存する。読み取れない対象は、名前を推測せず、共有に含めない。
enum AppNameResolver {
    static func name(for item: RestrictedItem) -> String? {
        switch item {
        case .app(let token): return Application(token: token).localizedDisplayName
        case .category(let token): return ActivityCategory(token: token).localizedDisplayName
        case .web(let token): return WebDomain(token: token).domain
        }
    }

    private static func keys(_ session: Session) -> [RestrictedItem] {
        RestrictedItems.decode(session.temporaryUnlockedApps).sortedItems
    }

    /// 共有用：期間ごとの、名前つきの回数。
    static func counts(sessions: [Session], mode: AppMode) -> (DateInterval) -> [AppCount] {
        { interval in
            AppUsageSummary.top(sessions: sessions, mode: mode, interval: interval, keys: keys, name: name(for:))
        }
    }

    /// 期間内に解除した対象の数と、そのうち名前を読み取れた数（画面で、取れなかった理由を正直に伝えるため）。
    static func availability(sessions: [Session], mode: AppMode, interval: DateInterval?) -> (total: Int, named: Int) {
        var items = Set<RestrictedItem>()
        for session in sessions {
            guard session.mode == mode, session.phase == .completed, session.outcome == .wantsToUse,
                  let at = session.temporaryUnlockStartedAt else { continue }
            if let interval, !interval.contains(at) { continue }
            items.formUnion(keys(session))
        }
        return (items.count, items.filter { name(for: $0).flatMap(AppUsageSummary.cleanName) != nil }.count)
    }
}
