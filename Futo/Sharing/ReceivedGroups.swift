import Foundation

/// 届いた記録を、送ってきた人ごとにまとめたもの。
struct ReceivedGroup: Identifiable, Equatable {
    /// サーバーが付けた、送り主ごとの目印（送り主のIDそのものではない）
    var id: String
    /// 名前を出していない送り主は nil
    var name: String?
    var avatar: AvatarSpec?
    /// 新しい順
    var items: [ReceivedFriendShare]

    /// その人の、いちばん新しい更新
    var latest: String { items.first.map { $0.updatedAt ?? $0.createdAt } ?? "" }
}

enum ReceivedGrouping {
    /// 送り主ごとにまとめる。グループは、記録が新しい人から。グループの中も、新しい順。
    /// 目印のない古いサーバーの応答は、名前でまとめる（名前を出していないものは、まとめて1つ）。
    static func group(_ items: [ReceivedFriendShare]) -> [ReceivedGroup] {
        var order: [String] = []
        var byKey: [String: ReceivedGroup] = [:]
        for item in items {
            let key = item.ownerKey ?? "name:\(item.ownerName ?? "")"
            if var group = byKey[key] {
                group.items.append(item)
                if group.avatar == nil { group.avatar = item.ownerAvatar }
                byKey[key] = group
            } else {
                order.append(key)
                byKey[key] = ReceivedGroup(id: key, name: item.ownerName, avatar: item.ownerAvatar, items: [item])
            }
        }
        let groups = order.compactMap { byKey[$0] }.map { group -> ReceivedGroup in
            var g = group
            g.items.sort { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
            return g
        }
        return groups.sorted { $0.latest > $1.latest }
    }
}
