import Foundation

/// サーバーAPIの応答（`web/` のAPIと同じ形）。

struct MeResponse: Codable, Equatable {
    var uid: String
    var displayName: String
    var status: String
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

struct RotatedShareResponse: Codable, Equatable {
    var token: String
    var expiresAt: String
    var url: String
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
        var id: String { friendshipId }
    }
    struct Incoming: Codable, Equatable, Identifiable {
        var requestId: String
        var uid: String
        var displayName: String
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
    var apps: [AppCount]?
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
