import Foundation

/// サーバーAPIの応答（`web/` のAPIと同じ形）。

/// アイコンの設定（フレンドにも見える）。`symbol` は絵の番号（nil は無印）、`color` はテーマの4色の番号。
struct AvatarSpec: Codable, Equatable {
    var symbol: Int?
    var color: Int
    /// 好きな色（「#RRGGBB」）。あれば、`color` より、こちらを使う
    var hex: String? = nil

    init(symbol: Int?, color: Int, hex: String? = nil) { self.symbol = symbol; self.color = color; self.hex = hex }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        symbol = try c.decodeIfPresent(Int.self, forKey: .symbol)
        color = try c.decode(Int.self, forKey: .color)
        hex = try c.decodeIfPresent(String.self, forKey: .hex)
    }

    /// 無印は、キーを省かず null で送る（サーバーが、無印を明示として受け取る）。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(color, forKey: .color)
        try c.encodeIfPresent(hex, forKey: .hex)
    }

    private enum CodingKeys: String, CodingKey { case symbol, color, hex }
}

struct MeResponse: Codable, Equatable {
    var uid: String
    var displayName: String
    var status: String
    var avatar: AvatarSpec? = nil
    /// アカウントで加入しているプラン（"adFree" / "support"）。なければ nil
    var webPlan: String? = nil
}

/// プロフィールの更新（ニックネームと、アイコン）
struct MeUpdate: Encodable {
    var displayName: String
    var avatar: AvatarSpec?
}

struct CreatedShareResponse: Codable, Equatable {
    var shareId: String
    /// 作成時だけ返る。再送で作成済みだった場合は nil（共有一覧から、リンクを再発行する）
    var token: String?
    var replay: Bool
    var expiresAt: String
    var url: String?
}

struct ShareListItem: Codable, Equatable, Identifiable {
    struct Selected: Codable, Equatable { var counts: Bool; var purposes: Bool; var feelings: Bool; var phrase: Bool }
    var id: String
    var period: String
    var periodStart: String
    var periodEnd: String
    var selected: Selected
    var createdAt: String
    var expiresAt: String
    /// active / expired / revoked
    var status: String
}

struct ShareListResponse: Codable, Equatable {
    var items: [ShareListItem]
    var next: String?
}

struct InvitationResponse: Codable, Equatable {
    var inviteId: String
    var token: String
    var code: String
    var url: String
    var expiresAt: String
}

struct PublicInvitationResponse: Codable, Equatable {
    var inviterName: String
    var expiresAt: String
    /// リンクと同じ招待のコード（コード入力欄に、自動で入れるため）
    var code: String? = nil
}

struct FriendRequestResponse: Codable, Equatable {
    var requestId: String
    var status: String
}

struct FriendsResponse: Codable, Equatable {
    struct Friend: Codable, Equatable, Identifiable {
        var friendshipId: String
        var uid: String
        var displayName: String
        var avatar: AvatarSpec? = nil
        var id: String { friendshipId }
    }
    struct Incoming: Codable, Equatable, Identifiable {
        var requestId: String
        var uid: String
        var displayName: String
        var avatar: AvatarSpec? = nil
        var expiresAt: String
        var id: String { requestId }
    }
    struct Outgoing: Codable, Equatable, Identifiable {
        var requestId: String
        var displayName: String
        var expiresAt: String
        var id: String { requestId }
    }
    var friends: [Friend]
    var incoming: [Incoming]
    var outgoing: [Outgoing]
}

struct StatsSnapshotDTO: Codable, Equatable {
    struct Counts: Codable, Equatable { var wantsToUse: Int; var deferred: Int; var interrupted: Int }
    struct Purposes: Codable, Equatable { var contact: Int; var research: Int; var `break`: Int; var noReason: Int; var unanswered: Int }
    struct Feelings: Codable, Equatable { var satisfied: Int; var neutral: Int; var wishedLess: Int; var answered: Int }
    var period: String
    var periodStart: String
    var periodEnd: String
    var timezone: String
    var isPartial: Bool
    var counts: Counts?
    var purposes: Purposes?
    var feelings: Feelings?
    var restriction: RestrictionCounts?
    var phrase: String?
    var message: String?
}

struct ReceivedFriendShare: Codable, Equatable, Identifiable {
    var id: String
    var ownerName: String?
    var period: String
    var createdAt: String
    var updatedAt: String?
    var expiresAt: String
    /// 送り主ごとの目印（送り主のIDではない。まとめて見せるためだけに使う）
    var ownerKey: String? = nil
    var ownerAvatar: AvatarSpec? = nil
}

/// 削除（ブロック）したフレンド。解除するための一覧に使う。
struct BlockedUser: Codable, Equatable, Identifiable {
    var uid: String
    var displayName: String
    var avatar: AvatarSpec? = nil
    var id: String { uid }
}

struct BlockedListResponse: Codable, Equatable {
    var items: [BlockedUser]
}

/// 自分が作ったリンクの、中身（アプリの中で、確かめるため）。
struct OwnShareDetail: Codable, Equatable {
    var id: String
    var displayName: String?
    var createdAt: String
    var expiresAt: String
    var status: String
    var stats: StatsSnapshotDTO
}

struct ReceivedFriendSharesResponse: Codable, Equatable {
    var items: [ReceivedFriendShare]
}

struct SentFriendShare: Codable, Equatable, Identifiable {
    var id: String
    var period: String
    var recipientCount: Int
    var createdAt: String
    var updatedAt: String?
    var expiresAt: String
    var status: String
}

struct SentFriendSharesResponse: Codable, Equatable {
    var items: [SentFriendShare]
}

struct FriendShareDetail: Codable, Equatable {
    var id: String
    var ownerName: String?
    var ownerAvatar: AvatarSpec? = nil
    var isOwner: Bool
    var createdAt: String
    var updatedAt: String?
    var expiresAt: String
    var status: String
    var stats: StatsSnapshotDTO
}

struct DeletionResponse: Codable, Equatable {
    var status: String   // deleted / in_progress
}

struct EmptyResponse: Codable, Equatable {
    var ok: Bool?
}
