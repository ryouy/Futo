import Foundation

/// 「デモを試す」の、共有・フレンドの擬似サーバー。
/// 本物のサーバーと同じ形の応答を、アプリの中のメモリだけで返す。通信・ログイン・トークン・端末への保存は、一切しない。
/// 登場する人・記録は、すべて架空。デモを終えると、このオブジェクトごと捨てる。
actor DemoBackend {
    /// デモの自分のID（本物のアカウントとは無関係。端末にも保存しない）
    static let meUID = "demo-me"
    /// デモで使える招待コード（入力すると、架空の相手に申請できる）
    static let sampleCode = "DEMA23456789"
    /// デモのリンクは、開けない（`.invalid` は、決して存在しないドメインと定められている）
    static let linkHost = "https://demo.invalid"

    private struct Person {
        var uid: String
        var name: String
        var avatar: AvatarSpec
    }

    private struct FriendShare {
        var id: String
        var ownerUID: String
        var recipients: Set<String>
        var createdAt: Date
        var updatedAt: Date?
        var expiresAt: Date
        var status: String            // active / revoked
        var showName: Bool
        var stats: StatsSnapshotDTO
        var hiddenByMe = false        // 受け取った側（自分）が、削除した
    }

    private struct WebShare {
        var item: ShareListItem
        var stats: StatsSnapshotDTO
        var showName: Bool
    }

    private struct PendingIncoming {
        var request: FriendsResponse.Incoming
        var visibleAt: Date
    }

    private struct PendingOutgoing {
        var request: FriendsResponse.Outgoing
        var person: Person
        var acceptAt: Date
    }

    private let now: @Sendable () -> Date
    private var counter = 0
    private var me: MeResponse
    private var friends: [FriendsResponse.Friend] = []
    private var incoming: [PendingIncoming] = []
    private var outgoing: [PendingOutgoing] = []
    private var blocked: [BlockedUser] = []
    private var invitation: InvitationResponse?
    private var invitationArrival: Person?
    private var webShares: [WebShare] = []
    private var friendShares: [FriendShare] = []
    private let people: [String: Person]

    /// 招待を作ってから、架空の相手の申請が届くまで・申請を出してから承認されるまで（秒）
    static let arrivalDelay: TimeInterval = 2
    static let acceptDelay: TimeInterval = 3

    init(avatar: AvatarSpec?, now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
        me = MeResponse(uid: Self.meUID, displayName: tr("あなた（デモ）"), status: "active", avatar: avatar)
        let sakura = Person(uid: "demo-sakura", name: tr("さくら（デモ）"), avatar: AvatarSpec(symbol: 3, color: 0))
        let haruto = Person(uid: "demo-haruto", name: tr("はると（デモ）"), avatar: AvatarSpec(symbol: 1, color: 1))
        let ren = Person(uid: "demo-ren", name: tr("れん（デモ）"), avatar: AvatarSpec(symbol: 5, color: 2))
        let mio = Person(uid: "demo-mio", name: tr("みお（デモ）"), avatar: AvatarSpec(symbol: 6, color: 3))
        let yui = Person(uid: "demo-yui", name: tr("ゆい（デモ）"), avatar: AvatarSpec(symbol: 7, color: 1))
        people = Dictionary(uniqueKeysWithValues: [sakura, haruto, ren, mio, yui].map { ($0.uid, $0) })

        friends = [sakura, haruto].map { FriendsResponse.Friend(friendshipId: "demo-fs-\($0.uid)", uid: $0.uid, displayName: $0.name, avatar: $0.avatar) }
        let t = now()
        incoming = [PendingIncoming(request: FriendsResponse.Incoming(requestId: "demo-req-ren", uid: ren.uid, displayName: ren.name, avatar: ren.avatar,
                                                                      expiresAt: Self.iso(t.addingTimeInterval(7 * 86_400))), visibleAt: t)]
        invitationArrival = mio

        // 届いている記録（架空）
        let week = LogicalCalendar().weekInterval(containing: t)
        let lastWeek = LogicalCalendar().previousWeekInterval(before: t)
        friendShares = [
            FriendShare(id: "demo-fshare-1", ownerUID: sakura.uid, recipients: [Self.meUID], createdAt: t.addingTimeInterval(-3 * 86_400), updatedAt: t.addingTimeInterval(-2 * 3_600),
                        expiresAt: t.addingTimeInterval(20 * 86_400), status: "active", showName: true,
                        stats: Self.sampleStats(period: "thisWeek", interval: week, partial: true, deferred: 9, wants: 3, interrupted: 1,
                                                purposes: (2, 3, 2, 5, 0), feelings: (2, 1, 0), restriction: RestrictionCounts(pauses: 1, ends: 0),
                                                message: tr("今週は、少し減らせました"), now: t)),
            FriendShare(id: "demo-fshare-2", ownerUID: sakura.uid, recipients: [Self.meUID], createdAt: t.addingTimeInterval(-9 * 86_400), updatedAt: nil,
                        expiresAt: t.addingTimeInterval(14 * 86_400), status: "active", showName: true,
                        stats: Self.sampleStats(period: "lastWeek", interval: lastWeek, partial: false, deferred: 7, wants: 5, interrupted: 0,
                                                purposes: (3, 2, 3, 4, 0), feelings: (1, 2, 2), restriction: nil, message: nil, now: t)),
            FriendShare(id: "demo-fshare-3", ownerUID: haruto.uid, recipients: [Self.meUID], createdAt: t.addingTimeInterval(-86_400), updatedAt: nil,
                        expiresAt: t.addingTimeInterval(25 * 86_400), status: "active", showName: true,
                        stats: Self.sampleStats(period: "thisWeek", interval: week, partial: true, deferred: 4, wants: 6, interrupted: 2,
                                                purposes: (4, 1, 1, 6, 0), feelings: (1, 3, 2), restriction: nil, message: nil, now: t)),
        ]
    }

    // MARK: 窓口

    func handle(method: String, path rawPath: String, body: Data?) throws -> Data {
        let parts = rawPath.split(separator: "?", maxSplits: 1).map(String.init)
        let path = parts[0]
        let query = parts.count > 1 ? parts[1] : ""
        let segments = path.split(separator: "/").map(String.init)
        guard segments.first == "api", segments.count >= 2 else { throw Self.error(.notFound) }
        advance()
        switch (method, segments[1], segments.count) {
        case ("GET", "me", 2): return try encode(me)
        case ("PUT", "me", 2): return try encode(try updateMe(body))
        case ("GET", "shares", 2): return try encode(ShareListResponse(items: webShares.map(\.item).reversed(), next: nil))
        case ("POST", "shares", 2): return try encode(try createWebShare(body))
        case ("GET", "shares", 3): return try encode(try ownShare(segments[2]))
        case ("DELETE", "shares", 3): try revokeWebShare(segments[2]); return empty
        case ("GET", "friends", 2): return try encode(friendsResponse())
        case ("POST", "invitations", 2): return try encode(createInvitation())
        case ("DELETE", "invitations", 3): invitation = nil; return empty
        case ("POST", "friend-requests", 2): return try encode(try sendRequest(body))
        case ("POST", "friend-requests", 4): try respond(segments[2], accept: segments[3] == "accept"); return empty
        case ("DELETE", "friend-requests", 3): try cancelRequest(segments[2]); return empty
        case ("POST", "blocks", 3): try block(segments[2]); return empty
        case ("GET", "blocks", 2): return try encode(BlockedListResponse(items: blocked))
        case ("DELETE", "blocks", 3): blocked.removeAll { $0.uid == segments[2] }; return empty
        case ("GET", "friend-shares", 2): return try encode(query.contains("role=sent") ? AnyEncodableBox(sent()) : AnyEncodableBox(received()))
        case ("POST", "friend-shares", 2): return try encode(try createFriendShare(body))
        case ("GET", "friend-shares", 3): return try encode(try friendShareDetail(segments[2]))
        case ("PUT", "friend-shares", 3): try updateFriendShare(segments[2], body); return empty
        case ("DELETE", "friend-shares", 3): try revokeFriendShare(segments[2]); return empty
        case ("DELETE", "friend-shares", 4) where segments[3] == "received": hideReceived(segments[2]); return empty
        default: throw Self.error(.notFound)
        }
    }

    // MARK: プロフィール

    private func updateMe(_ body: Data?) throws -> MeResponse {
        struct Update: Decodable { var displayName: String; var avatar: AvatarSpec? }
        let update = try decode(Update.self, body)
        let name = update.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 20 else { throw Self.error(.invalid) }
        me.displayName = name
        me.avatar = update.avatar
        return me
    }

    // MARK: Web共有（リンク）

    private func createWebShare(_ body: Data?) throws -> CreatedShareResponse {
        let payload = try decode(SharePayload.self, body)
        let created = now()
        let days = min(max(payload.expiresInDays ?? 7, 1), 30)
        let expires = created.addingTimeInterval(Double(days) * 86_400)
        let id = nextID("share")
        let token = "demo" + String(repeating: "x", count: 4) + id
        let item = ShareListItem(id: id, period: payload.period, periodStart: payload.periodStart, periodEnd: payload.periodEnd,
                                 selected: .init(counts: payload.counts != nil, purposes: payload.purposes != nil, feelings: payload.feelings != nil, phrase: payload.phraseId != nil),
                                 createdAt: Self.iso(created), expiresAt: Self.iso(expires), status: "active")
        webShares.append(WebShare(item: item, stats: Self.snapshot(from: payload), showName: payload.showName))
        return CreatedShareResponse(shareId: id, token: token, replay: false, expiresAt: Self.iso(expires), url: "\(Self.linkHost)/s/\(token)")
    }

    private func ownShare(_ id: String) throws -> OwnShareDetail {
        guard let share = webShares.first(where: { $0.item.id == id }) else { throw Self.error(.notFound) }
        return OwnShareDetail(id: id, displayName: share.showName ? me.displayName : nil, createdAt: share.item.createdAt, expiresAt: share.item.expiresAt,
                              status: share.item.status, stats: share.stats)
    }

    private func revokeWebShare(_ id: String) throws {
        guard let index = webShares.firstIndex(where: { $0.item.id == id }) else { throw Self.error(.notFound) }
        webShares[index].item.status = "revoked"
    }

    // MARK: フレンド

    /// 時間がたって起こること（架空の相手の申請が届く・出した申請が承認される）を反映する。
    private func advance() {
        let t = now()
        for pending in outgoing where pending.acceptAt <= t {
            if !friends.contains(where: { $0.uid == pending.person.uid }) {
                friends.append(FriendsResponse.Friend(friendshipId: nextID("fs"), uid: pending.person.uid, displayName: pending.person.name, avatar: pending.person.avatar))
            }
        }
        outgoing.removeAll { $0.acceptAt <= t }
    }

    private func friendsResponse() -> FriendsResponse {
        let t = now()
        return FriendsResponse(friends: friends, incoming: incoming.filter { $0.visibleAt <= t }.map(\.request), outgoing: outgoing.map(\.request))
    }

    private func createInvitation() -> InvitationResponse {
        let t = now()
        let token = "demo" + nextID("inv")
        let created = InvitationResponse(inviteId: nextID("inv"), token: token, code: "DEMB23456789", url: "\(Self.linkHost)/i/\(token)",
                                         expiresAt: Self.iso(t.addingTimeInterval(7 * 86_400)))
        invitation = created
        // 招待を作ると、少しして、架空の相手が使ってくれる（承認の操作を試せる）
        if let person = invitationArrival, !incoming.contains(where: { $0.request.uid == person.uid }), !friends.contains(where: { $0.uid == person.uid }), !blocked.contains(where: { $0.uid == person.uid }) {
            incoming.append(PendingIncoming(request: FriendsResponse.Incoming(requestId: nextID("req"), uid: person.uid, displayName: person.name, avatar: person.avatar,
                                                                              expiresAt: Self.iso(t.addingTimeInterval(7 * 86_400))),
                                            visibleAt: t.addingTimeInterval(Self.arrivalDelay)))
        }
        return created
    }

    private func sendRequest(_ body: Data?) throws -> FriendRequestResponse {
        struct Body: Decodable { var token: String?; var code: String? }
        let input = try decode(Body.self, body)
        guard let code = input.code, InviteLink.normalizedCode(code) != nil else { throw Self.error(.notFound) }
        if let invitation, InviteLink.normalizedCode(invitation.code) == InviteLink.normalizedCode(code) { throw APIError(kind: .forbidden, code: "self_invite") }
        guard InviteLink.normalizedCode(code) == Self.sampleCode, let yui = people["demo-yui"] else { throw Self.error(.notFound) }
        if friends.contains(where: { $0.uid == yui.uid }) || outgoing.contains(where: { $0.person.uid == yui.uid }) { throw Self.error(.conflict) }
        if blocked.contains(where: { $0.uid == yui.uid }) { throw Self.error(.forbidden) }
        let t = now()
        let id = nextID("req")
        outgoing.append(PendingOutgoing(request: FriendsResponse.Outgoing(requestId: id, displayName: yui.name, expiresAt: Self.iso(t.addingTimeInterval(7 * 86_400))),
                                        person: yui, acceptAt: t.addingTimeInterval(Self.acceptDelay)))
        return FriendRequestResponse(requestId: id, status: "pending")
    }

    private func respond(_ id: String, accept: Bool) throws {
        guard let index = incoming.firstIndex(where: { $0.request.requestId == id }) else { throw Self.error(.notFound) }
        let request = incoming.remove(at: index).request
        if accept {
            friends.append(FriendsResponse.Friend(friendshipId: nextID("fs"), uid: request.uid, displayName: request.displayName, avatar: request.avatar))
        }
    }

    private func cancelRequest(_ id: String) throws {
        guard outgoing.contains(where: { $0.request.requestId == id }) else { throw Self.error(.notFound) }
        outgoing.removeAll { $0.request.requestId == id }
    }

    /// 削除（ブロック）。関係を終わらせ、その人の記録は、届かなくなる。
    private func block(_ uid: String) throws {
        guard let friend = friends.first(where: { $0.uid == uid }) else { throw Self.error(.notFound) }
        friends.removeAll { $0.uid == uid }
        if !blocked.contains(where: { $0.uid == uid }) { blocked.append(BlockedUser(uid: uid, displayName: friend.displayName, avatar: friend.avatar)) }
        for index in friendShares.indices {
            if friendShares[index].ownerUID == uid { friendShares[index].status = "revoked" }
            friendShares[index].recipients.remove(uid)
        }
    }

    // MARK: フレンド限定共有

    private func received() -> ReceivedFriendSharesResponse {
        let items = friendShares.filter { $0.ownerUID != Self.meUID && $0.recipients.contains(Self.meUID) && $0.status == "active" && !$0.hiddenByMe }
            .compactMap { share -> ReceivedFriendShare? in
                guard let owner = people[share.ownerUID] else { return nil }
                return ReceivedFriendShare(id: share.id, ownerName: share.showName ? owner.name : nil, period: share.stats.period, createdAt: Self.iso(share.createdAt),
                                           updatedAt: share.updatedAt.map(Self.iso), expiresAt: Self.iso(share.expiresAt),
                                           ownerKey: share.showName ? "owner-\(owner.uid)" : "anonymous", ownerAvatar: share.showName ? owner.avatar : nil)
            }
        return ReceivedFriendSharesResponse(items: items)
    }

    private func sent() -> SentFriendSharesResponse {
        SentFriendSharesResponse(items: friendShares.filter { $0.ownerUID == Self.meUID }.map {
            SentFriendShare(id: $0.id, period: $0.stats.period, recipientCount: $0.recipients.count, createdAt: Self.iso($0.createdAt),
                            updatedAt: $0.updatedAt.map(Self.iso), expiresAt: Self.iso($0.expiresAt), status: $0.status)
        })
    }

    private func createFriendShare(_ body: Data?) throws -> CreatedShareResponse {
        let payload = try decode(SharePayload.self, body)
        let recipients = Set(payload.recipientUids ?? [])
        // 受け取れるのは、いまのフレンドだけ
        guard !recipients.isEmpty, recipients.allSatisfy({ uid in friends.contains { $0.uid == uid } }) else { throw Self.error(.forbidden) }
        let created = now()
        let id = nextID("fshare")
        let expires = created.addingTimeInterval(30 * 86_400)
        friendShares.append(FriendShare(id: id, ownerUID: Self.meUID, recipients: recipients, createdAt: created, updatedAt: nil, expiresAt: expires,
                                        status: "active", showName: payload.showName, stats: Self.snapshot(from: payload)))
        return CreatedShareResponse(shareId: id, token: nil, replay: false, expiresAt: Self.iso(expires), url: nil)
    }

    private func friendShareDetail(_ id: String) throws -> FriendShareDetail {
        guard let share = friendShares.first(where: { $0.id == id }), share.status == "active" else { throw Self.error(.notFound) }
        if share.ownerUID == Self.meUID {
            return FriendShareDetail(id: id, ownerName: share.showName ? me.displayName : nil, ownerAvatar: share.showName ? me.avatar : nil, isOwner: true,
                                     createdAt: Self.iso(share.createdAt), updatedAt: share.updatedAt.map(Self.iso), expiresAt: Self.iso(share.expiresAt), status: share.status, stats: share.stats)
        }
        guard share.recipients.contains(Self.meUID), !share.hiddenByMe, let owner = people[share.ownerUID] else { throw Self.error(.forbidden) }
        return FriendShareDetail(id: id, ownerName: share.showName ? owner.name : nil, ownerAvatar: share.showName ? owner.avatar : nil, isOwner: false,
                                 createdAt: Self.iso(share.createdAt), updatedAt: share.updatedAt.map(Self.iso), expiresAt: Self.iso(share.expiresAt), status: share.status, stats: share.stats)
    }

    private func updateFriendShare(_ id: String, _ body: Data?) throws {
        let update = try decode(ShareUpdatePayload.self, body)
        guard let index = friendShares.firstIndex(where: { $0.id == id && $0.ownerUID == Self.meUID }), friendShares[index].status == "active" else { throw Self.error(.notFound) }
        friendShares[index].stats = Self.snapshot(from: update)
        friendShares[index].showName = update.showName
        friendShares[index].updatedAt = now()
    }

    private func revokeFriendShare(_ id: String) throws {
        guard let index = friendShares.firstIndex(where: { $0.id == id && $0.ownerUID == Self.meUID }) else { throw Self.error(.notFound) }
        friendShares[index].status = "revoked"
    }

    private func hideReceived(_ id: String) {
        if let index = friendShares.firstIndex(where: { $0.id == id && $0.ownerUID != Self.meUID }) { friendShares[index].hiddenByMe = true }
    }

    // MARK: 道具

    private var empty: Data { Data("{\"ok\":true}".utf8) }

    private func nextID(_ prefix: String) -> String {
        counter += 1
        return "demo-\(prefix)-\(counter)"
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data { try JSONEncoder().encode(value) }

    private func decode<T: Decodable>(_ type: T.Type, _ body: Data?) throws -> T {
        guard let body, let value = try? JSONDecoder().decode(T.self, from: body) else { throw Self.error(.invalid) }
        return value
    }

    private static func error(_ kind: APIError.Kind) -> APIError { APIError(kind: kind, code: nil) }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    // MARK: 統計

    private static func snapshot(from payload: SharePayload) -> StatsSnapshotDTO {
        StatsSnapshotDTO(
            period: payload.period, periodStart: payload.periodStart, periodEnd: payload.periodEnd, timezone: payload.timezone, isPartial: payload.isPartial,
            counts: payload.counts.map { .init(wantsToUse: $0.wantsToUse, deferred: $0.deferred, interrupted: $0.interrupted) },
            purposes: payload.purposes.map { .init(contact: $0.contact, research: $0.research, break: $0.break, noReason: $0.noReason, unanswered: $0.unanswered) },
            feelings: payload.feelings.map { .init(satisfied: $0.satisfied, neutral: $0.neutral, wishedLess: $0.wishedLess, answered: $0.satisfied + $0.neutral + $0.wishedLess) },
            restriction: payload.restriction, phrase: payload.phraseId.flatMap(SharePhrase.init(rawValue:))?.text, message: payload.message)
    }

    private static func snapshot(from update: ShareUpdatePayload) -> StatsSnapshotDTO {
        StatsSnapshotDTO(
            period: update.period, periodStart: update.periodStart, periodEnd: update.periodEnd, timezone: update.timezone, isPartial: update.isPartial,
            counts: update.counts.map { .init(wantsToUse: $0.wantsToUse, deferred: $0.deferred, interrupted: $0.interrupted) },
            purposes: update.purposes.map { .init(contact: $0.contact, research: $0.research, break: $0.break, noReason: $0.noReason, unanswered: $0.unanswered) },
            feelings: update.feelings.map { .init(satisfied: $0.satisfied, neutral: $0.neutral, wishedLess: $0.wishedLess, answered: $0.satisfied + $0.neutral + $0.wishedLess) },
            restriction: update.restriction, phrase: update.phraseId.flatMap(SharePhrase.init(rawValue:))?.text, message: update.message)
    }

    private static func sampleStats(period: String, interval: DateInterval, partial: Bool, deferred: Int, wants: Int, interrupted: Int,
                                    purposes: (Int, Int, Int, Int, Int), feelings: (Int, Int, Int), restriction: RestrictionCounts?, message: String?, now: Date) -> StatsSnapshotDTO {
        StatsSnapshotDTO(
            period: period, periodStart: iso(interval.start), periodEnd: iso(interval.end), timezone: TimeZone.current.identifier, isPartial: partial,
            counts: .init(wantsToUse: wants, deferred: deferred, interrupted: interrupted),
            purposes: .init(contact: purposes.0, research: purposes.1, break: purposes.2, noReason: purposes.3, unanswered: purposes.4),
            feelings: .init(satisfied: feelings.0, neutral: feelings.1, wishedLess: feelings.2, answered: feelings.0 + feelings.1 + feelings.2),
            restriction: restriction, phrase: nil, message: message)
    }
}

/// 型の違う応答を、同じ分岐で返すための包み。
private struct AnyEncodableBox: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// デモの継続共有の設定の保管。端末には保存せず、メモリだけに置く。
final class InMemoryStandingStore: StandingShareStoring {
    private var storage: [String: [StandingShareConfig]] = [:]
    func load(uid: String) -> [StandingShareConfig] { storage[uid] ?? [] }
    func save(_ configs: [StandingShareConfig], uid: String) { storage[uid] = configs }
}
