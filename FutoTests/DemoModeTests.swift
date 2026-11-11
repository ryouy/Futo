import XCTest
@testable import Futo

/// 「デモを試す」：ログインなしで、架空のデータで、共有・フレンドの操作を試せる。
/// 通信しない・保存しない・ログイン状態を変えない・終えたら全部消える、を確かめる。
@MainActor
final class DemoModeTests: XCTestCase {
    private let config = Phase4Config(plist: ["APIBaseURL": "https://share.example.test", "FirebaseAPIKey": "API-KEY", "GoogleClientID": "123-abc.apps.googleusercontent.com"])
    private var networkRequests = 0
    private var store = MemoryStore()

    override func setUp() {
        LanguageStore.shared.select(.ja)
        networkRequests = 0
        store = MemoryStore()
        StubProtocol.handler = { [unowned self] _ in networkRequests += 1; return (500, Data()) }
    }

    override func tearDown() { StubProtocol.handler = nil }

    private func makeModel(signedIn: Bool = false) -> SharingModel {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: c)
        if signedIn { store.saved = StoredAuthSession(uid: "real-uid", refreshToken: "r", provider: "google") }
        let auth = AuthService(config: config, urlSession: session, web: FakeWeb { _ in throw AuthError.cancelled }, store: store)
        return SharingModel(config: config, auth: auth, urlSession: session, standingStore: InMemoryStandingStore())
    }

    private func friend(_ model: SharingModel, _ name: String) -> FriendsResponse.Friend? {
        model.friends.friends.first { $0.displayName.contains(name) }
    }

    // MARK: 入口と状態

    func testDemoIsOfferedOnlyWhenSignedOut() async {
        let signedOut = makeModel()
        XCTAssertTrue(signedOut.canTryDemo)
        let signedIn = makeModel(signedIn: true)
        XCTAssertFalse(signedIn.canTryDemo)
        await signedIn.enterDemo()
        XCTAssertFalse(signedIn.isDemo, "ログイン中は、デモに入れない（本物のアカウントと混ぜない）")
        XCTAssertEqual(signedIn.uid, "real-uid")
    }

    func testEnteringDemoDoesNotTouchRealAuthOrNetwork() async {
        let model = makeModel()
        await model.enterDemo()
        XCTAssertTrue(model.isDemo)
        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(model.auth.state, .signedOut, "本物のログイン状態は変わらない")
        XCTAssertNil(store.saved, "ログイン情報は保存されない")
        XCTAssertEqual(model.uid, DemoBackend.meUID)
        XCTAssertNotNil(model.profile)
        XCTAssertEqual(networkRequests, 0, "デモは、通信しない")
    }

    // MARK: 主要な操作

    func testFriendsAndReceivedRecordsAreSeededWithFictionalPeople() async {
        let model = makeModel()
        await model.enterDemo()
        XCTAssertEqual(model.friends.friends.count, 2)
        XCTAssertEqual(model.friends.incoming.count, 1, "承認待ちが、はじめからある")
        XCTAssertEqual(model.receivedShares.count, 3)
        XCTAssertTrue(model.friends.friends.allSatisfy { $0.displayName.contains("デモ") })
        let detail = await model.friendShareDetail(id: model.receivedShares[0].id)
        XCTAssertEqual(detail?.isOwner, false)
        XCTAssertNotNil(detail?.stats.counts)
    }

    func testAcceptingAndDecliningRequests() async throws {
        let model = makeModel()
        await model.enterDemo()
        let request = try XCTUnwrap(model.friends.incoming.first)
        await model.respond(to: request, accept: true)
        XCTAssertTrue(model.friends.incoming.isEmpty)
        XCTAssertNotNil(friend(model, "れん"))
        XCTAssertEqual(networkRequests, 0)
    }

    func testInvitationBringsAFictionalRequestThatCanBeApproved() async throws {
        let model = makeModel()
        await model.enterDemo()
        await model.respond(to: model.friends.incoming[0], accept: false)
        await model.createInvitation()
        let invitation = try XCTUnwrap(model.invitation)
        XCTAssertNotNil(InviteLink.normalizedCode(invitation.code))
        XCTAssertTrue(invitation.url.hasPrefix("https://demo.invalid/"), "デモの招待リンクは、実在しない宛先")
        XCTAssertTrue(model.friends.incoming.isEmpty, "申請が届くまで、少し待つ")
        try await Task.sleep(for: .seconds(DemoBackend.arrivalDelay + 0.8))
        XCTAssertEqual(model.friends.incoming.count, 1, "架空の相手が、招待を使ってくれる")
        await model.respond(to: model.friends.incoming[0], accept: true)
        XCTAssertNotNil(friend(model, "みお"))
    }

    func testSendingRequestWithTheDemoCodeIsAcceptedLater() async throws {
        let model = makeModel()
        await model.enterDemo()
        let ok = await model.sendFriendRequest(code: DemoBackend.sampleCode)
        XCTAssertTrue(ok)
        XCTAssertEqual(model.friends.outgoing.count, 1)
        try await Task.sleep(for: .seconds(DemoBackend.acceptDelay + 0.8))
        XCTAssertTrue(model.friends.outgoing.isEmpty)
        XCTAssertNotNil(friend(model, "ゆい"))
        let unknown = await model.sendFriendRequest(code: "ABCDEFGHJKMN")
        XCTAssertFalse(unknown, "デモに無いコードは、見つからない")
    }

    func testInviteLinksFromOutsideAreIgnoredInDemo() async {
        let model = makeModel()
        await model.enterDemo()
        model.handleIncoming(url: URL(string: "futo://invite/\(String(repeating: "a", count: 43))")!)
        XCTAssertFalse(model.openFriendsPending)
        XCTAssertEqual(networkRequests, 0)
    }

    func testWebShareCreateViewAndRevokeUseFictionalRecords() async throws {
        let model = makeModel()
        await model.enterDemo()
        let payload = try model.previewPayload(sessions: [], mode: .device, period: .all, selection: .allIncluded, expiresInDays: 7)
        XCTAssertGreaterThan((payload.counts?.deferred ?? 0) + (payload.counts?.wantsToUse ?? 0), 0, "端末の記録が空でも、架空の記録から作る")
        let url = await model.createWebShare(payload)
        XCTAssertEqual(url?.host, "demo.invalid")
        XCTAssertEqual(model.shares.count, 1)
        let item = try XCTUnwrap(model.shares.first)
        XCTAssertEqual(model.localURL(for: item), url)
        let own = await model.loadOwnShare(id: item.id)
        XCTAssertEqual(own?.stats.counts?.deferred, payload.counts?.deferred)
        await model.revokeShare(item)
        XCTAssertEqual(model.shares.first?.status, "revoked")
        XCTAssertEqual(networkRequests, 0)
    }

    func testFriendShareStandingUpdateAndRevoke() async throws {
        let model = makeModel()
        await model.enterDemo()
        let sakura = try XCTUnwrap(friend(model, "さくら"))
        let payload = try model.previewPayload(sessions: [], mode: .device, period: .thisWeek, selection: .allIncluded, expiresInDays: nil, recipientUids: [sakura.uid])
        let created = await model.createFriendShare(payload, standing: (.thisWeek, .allIncluded))
        XCTAssertTrue(created)
        XCTAssertEqual(model.sentShares.count, 1)
        XCTAssertEqual(model.sentShares[0].recipientCount, 1)
        XCTAssertEqual(model.standingConfigs.count, 1, "継続共有の設定は、メモリだけに置く")
        await model.refreshStanding(sessions: [], mode: .device, force: true)
        XCTAssertNotNil(model.sentShares.first?.updatedAt)
        await model.revokeFriendShare(id: model.sentShares[0].id)
        XCTAssertEqual(model.sentShares.first?.status, "revoked")
        // フレンドでない相手には、共有できない
        let stranger = try model.previewPayload(sessions: [], mode: .device, period: .thisWeek, selection: .allIncluded, expiresInDays: nil, recipientUids: ["demo-yui"])
        let rejected = await model.createFriendShare(stranger)
        XCTAssertFalse(rejected)
    }

    func testBlockingAFriendRemovesTheirRecordsAndCanBeUndone() async throws {
        let model = makeModel()
        await model.enterDemo()
        let sakura = try XCTUnwrap(friend(model, "さくら"))
        XCTAssertEqual(model.receivedShares.filter { $0.ownerName?.contains("さくら") == true }.count, 2)
        await model.deleteFriend(sakura)
        XCTAssertNil(friend(model, "さくら"))
        XCTAssertEqual(model.blocked.count, 1)
        XCTAssertTrue(model.receivedShares.allSatisfy { $0.ownerName?.contains("さくら") != true }, "ブロックした人の記録は、届かなくなる")
        await model.unblock(model.blocked[0])
        XCTAssertTrue(model.blocked.isEmpty)
        XCTAssertNil(friend(model, "さくら"), "ブロックを解除しても、フレンドには戻らない")
    }

    func testRemovingReceivedRecordAndEditingProfile() async throws {
        let model = makeModel()
        await model.enterDemo()
        let id = model.receivedShares[0].id
        await model.removeReceived(ids: [id])
        XCTAssertFalse(model.receivedShares.contains { $0.id == id })
        let saved = await model.saveDisplayName("レビュー担当")
        XCTAssertTrue(saved)
        XCTAssertEqual(model.profile?.displayName, "レビュー担当")
        let empty = await model.saveDisplayName("  ")
        XCTAssertFalse(empty)
    }

    // MARK: 終了後

    func testExitingDemoErasesEverythingAndReturnsToSignedOut() async throws {
        let model = makeModel()
        let before = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("demo") }
        await model.enterDemo()
        let payload = try model.previewPayload(sessions: [], mode: .device, period: .all, selection: .allIncluded, expiresInDays: 7)
        _ = await model.createWebShare(payload)
        await model.createInvitation()
        let sakura = try XCTUnwrap(friend(model, "さくら"))
        await model.deleteFriend(sakura)
        model.markSeen(id: "x", version: "1")
        AvatarSettings.shared.selectSymbol(2)

        model.exitDemo()
        XCTAssertFalse(model.isDemo)
        XCTAssertFalse(model.isSignedIn)
        XCTAssertNil(model.uid)
        XCTAssertNil(model.profile)
        XCTAssertTrue(model.friends.friends.isEmpty && model.friends.incoming.isEmpty && model.friends.outgoing.isEmpty)
        XCTAssertTrue(model.shares.isEmpty && model.receivedShares.isEmpty && model.sentShares.isEmpty && model.blocked.isEmpty)
        XCTAssertNil(model.invitation)
        XCTAssertNil(model.lastCreatedURL)
        XCTAssertTrue(model.standingConfigs.isEmpty)
        XCTAssertNil(AvatarSettings.shared.symbolIndex, "デモで選んだアイコンは、残らない")
        XCTAssertEqual(model.auth.state, .signedOut)
        XCTAssertTrue(model.canTryDemo, "通常のログイン画面に戻る")
        XCTAssertEqual(networkRequests, 0)
        // 端末（UserDefaults）に、デモのデータは、残らない
        let after = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.contains("demo") }
        XCTAssertEqual(Set(after), Set(before))
        // もう一度入ると、最初からやり直せる
        await model.enterDemo()
        XCTAssertEqual(model.friends.friends.count, 2)
        XCTAssertTrue(model.shares.isEmpty)
        model.exitDemo()
    }

    func testRealSignInStaysAvailableAndDemoDoesNotLeakIntoIt() async {
        let model = makeModel()
        await model.enterDemo()
        model.exitDemo()
        await model.signIn()   // FakeWeb は、取りやめ
        XCTAssertFalse(model.isSignedIn, "デモを経ても、本物のログインは、本物の認証が必要")
        XCTAssertEqual(networkRequests, 0)
    }

    func testSignOutDuringDemoJustEndsTheDemo() async {
        let model = makeModel()
        await model.enterDemo()
        model.signOut()
        XCTAssertFalse(model.isDemo)
    }

    func testDemoRecordsNeverComeFromTheDeviceRecords() async throws {
        let model = makeModel()
        await model.enterDemo()
        let real = Session(mode: .device, startedAt: Date(), requiredWaitSeconds: 60)
        real.phase = .completed; real.outcome = .interrupted
        let payload = try model.previewPayload(sessions: [real], mode: .device, period: .all, selection: .allIncluded, expiresInDays: 7)
        XCTAssertEqual(payload.counts?.interrupted, 0, "デモでは、端末の本物の記録を使わない")
    }

    func testDemoBackendRejectsUnknownEndpointsAndBadInput() async throws {
        let backend = DemoBackend(avatar: nil)
        do { _ = try await backend.handle(method: "GET", path: "/api/admin", body: nil); XCTFail() } catch let error as APIError { XCTAssertEqual(error.kind, .notFound) }
        do { _ = try await backend.handle(method: "DELETE", path: "/api/me", body: nil); XCTFail("アカウント削除は、デモに無い") } catch let error as APIError { XCTAssertEqual(error.kind, .notFound) }
        do { _ = try await backend.handle(method: "POST", path: "/api/shares", body: Data("{}".utf8)); XCTFail() } catch let error as APIError { XCTAssertEqual(error.kind, .invalid) }
    }
}
