import SwiftData
import XCTest
@testable import Futo

// MARK: - PKCE・招待リンク・設定

final class SharingBasicsTests: XCTestCase {
    func testCustomSchemeInviteOpensOnlyTheInviteAndNeverOtherPaths() {
        let token = String(repeating: "a", count: 43)
        XCTAssertEqual(InviteLink.token(from: URL(string: "futo://invite/\(token)")!, allowedHost: nil), token)
        XCTAssertEqual(InviteLink.token(from: URL(string: "FUTO://invite/\(token)")!, allowedHost: "share.example.test"), token)
        XCTAssertNil(InviteLink.token(from: URL(string: "futo://share/\(token)")!, allowedHost: nil), "招待以外は処理しない")
        XCTAssertNil(InviteLink.token(from: URL(string: "futo://invite/short")!, allowedHost: nil))
        XCTAssertNil(InviteLink.token(from: URL(string: "futo://invite/\(token)/extra")!, allowedHost: nil))
        XCTAssertNil(InviteLink.token(from: URL(string: "futo://evil.example/invite/\(token)")!, allowedHost: nil))
    }

    func testPKCEMatchesTheRFC7636TestVector() {
        // RFC 7636 付録B のテストベクタ
        XCTAssertEqual(PKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testPKCEVerifierIsLongRandomAndURLSafe() {
        let a = PKCE.randomString(), b = PKCE.randomString()
        XCTAssertNotEqual(a, b)
        XCTAssertGreaterThanOrEqual(a.count, 43)
        XCTAssertTrue(a.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
    }

    private let token = String(repeating: "a", count: 43)

    func testInviteLinkAcceptsOnlyTheAllowedHostAndPath() {
        let host = "share.example.test"
        XCTAssertEqual(InviteLink.token(from: URL(string: "https://share.example.test/i/\(token)")!, allowedHost: host), token)
        XCTAssertEqual(InviteLink.token(from: URL(string: "https://SHARE.example.test/i/\(token)")!, allowedHost: host), token)
        let rejected = [
            "http://share.example.test/i/\(token)",                    // httpは不可
            "https://share.example.test/s/\(token)",                   // 統計共有のリンクは、アプリでは処理しない
            "https://share.example.test/i/\(token)/extra",
            "https://share.example.test/i/short",
            "https://share.example.test/i/\(String(repeating: "あ", count: 43))",
            "https://share.example.test.evil.com/i/\(token)",          // 似たホスト
            "https://evil.com/i/\(token)",
            "https://share.example.test@evil.com/i/\(token)",          // ユーザー情報で偽装
            "https://user:pass@share.example.test/i/\(token)",
            "https://share.example.test:8443/i/\(token)",
            "futo://i/\(token)",
        ]
        for text in rejected {
            XCTAssertNil(InviteLink.token(from: URL(string: text)!, allowedHost: host), text)
        }
        XCTAssertNil(InviteLink.token(from: URL(string: "https://share.example.test/i/\(token)")!, allowedHost: nil), "未設定のときは何も処理しない")
    }

    func testInviteCodeNormalization() {
        XCTAssertEqual(InviteLink.normalizedCode("abcd-efgh jkmn"), "ABCDEFGHJKMN")
        XCTAssertNil(InviteLink.normalizedCode("ABCDEFGHJKM"))       // 11文字
        XCTAssertNil(InviteLink.normalizedCode("ABCDEFGHJKMNP"))     // 13文字
        XCTAssertNil(InviteLink.normalizedCode("ABCDEFGHJKM0"))      // 紛らわしい文字は使わない
        XCTAssertNil(InviteLink.normalizedCode("ABCDEFGHJKMI"))
        XCTAssertNil(InviteLink.normalizedCode("１２３４５６７８９０１２"))   // 全角の数字
    }

    func testConfigRequiresHTTPSAndAllValues() {
        XCTAssertFalse(Phase4Config.empty.isConfigured)
        let ok = Phase4Config(plist: ["APIBaseURL": "https://share.example.test", "FirebaseAPIKey": "key", "GoogleClientID": "123-abc.apps.googleusercontent.com"])
        XCTAssertTrue(ok.isConfigured)
        XCTAssertEqual(ok.allowedHost, "share.example.test")
        XCTAssertEqual(ok.googleRedirectScheme, "com.googleusercontent.apps.123-abc")
        let insecure = Phase4Config(plist: ["APIBaseURL": "http://share.example.test", "FirebaseAPIKey": "key", "GoogleClientID": "x.apps.googleusercontent.com"])
        XCTAssertNil(insecure.apiBaseURL, "共有データを送る先は、HTTPSだけ")
        XCTAssertFalse(insecure.isConfigured)
        XCTAssertFalse(Phase4Config(plist: ["APIBaseURL": "https://a.test", "FirebaseAPIKey": "", "GoogleClientID": "x"]).isConfigured)
    }
}

// MARK: - 共有する統計の作成

@MainActor
final class ShareStatsTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!
    private var cal: LogicalCalendar!

    override func setUp() async throws {
        container = try ModelContainer(for: Session.self, ReflectionCard.self, RestrictionEvent.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        calendar.firstWeekday = 2
        cal = LogicalCalendar(calendar: calendar)
    }

    private func jst(_ text: String) -> Date {
        let f = DateFormatter()
        f.calendar = cal.calendar; f.timeZone = cal.calendar.timeZone; f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.date(from: text)!
    }

    @discardableResult
    private func record(_ at: String, mode: AppMode = .device, purpose: Purpose? = nil, outcome: SessionOutcome? = .deferred,
                        reflection: Reflection? = nil, open: Bool = false) -> Session {
        let s = Session(mode: mode, startedAt: jst(at), requiredWaitSeconds: 180)
        s.purpose = purpose; s.outcome = outcome; s.reflection = reflection
        s.phase = open ? .waiting : (outcome == .interrupted ? .interrupted : .completed)
        context.insert(s)
        return s
    }

    private func all() -> [Session] { (try? context.fetch(FetchDescriptor<Session>())) ?? [] }
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func build(_ selection: ShareSelection, period: SharePeriod = .thisWeek, at: String = "2027-01-13 20:00") throws -> SharePayload {
        try ShareStatsBuilder.make(sessions: all(), mode: .device, period: period, selection: selection, calendar: cal, now: jst(at),
                                   idempotencyKey: "11111111-1111-4111-8111-111111111111")
    }

    func testNothingSelectedIsRefused() {
        XCTAssertThrowsError(try build(ShareSelection())) { XCTAssertEqual($0 as? ShareStatsBuilder.BuildError, .nothingSelected) }
        var onlyPhrase = ShareSelection(); onlyPhrase.phrase = .p1
        XCTAssertThrowsError(try build(onlyPhrase), "ひとことだけの共有は作らない")
    }

    func testDefaultSelectionPublishesNothingBeyondTheName() {
        let s = ShareSelection()
        XCTAssertTrue(s.showName)
        XCTAssertFalse(s.counts || s.purposes || s.feelings)
        XCTAssertNil(s.phrase)
    }

    func testCountsUseTheSameWeekDefinitionAsPersonalStats() throws {
        // 2027-01-13(水)。今週=1/11 04:00〜。月曜の深夜2時は、先週に数える
        record("2027-01-11 02:00", outcome: .deferred)      // 先週
        record("2027-01-11 05:00", outcome: .wantsToUse)    // 今週
        record("2027-01-12 10:00", outcome: .deferred)
        record("2027-01-12 11:00", outcome: .interrupted)
        record("2027-01-13 09:00", outcome: nil)            // 結果なし＝中断に数える
        record("2027-01-13 09:30", outcome: .deferred, open: true)   // 進行中は含めない
        record("2027-01-12 12:00", mode: .demo, outcome: .deferred) // デモは混ぜない
        var selection = ShareSelection(); selection.counts = true

        let thisWeek = try build(selection)
        XCTAssertEqual(thisWeek.counts, .init(wantsToUse: 1, deferred: 1, interrupted: 2))
        XCTAssertTrue(thisWeek.isPartial)
        XCTAssertEqual(thisWeek.period, "thisWeek")
        XCTAssertEqual(thisWeek.timezone, "Asia/Tokyo")
        XCTAssertEqual(thisWeek.periodStart, "2027-01-10T19:00:00.000Z")   // 1/11 04:00 JST
        XCTAssertEqual(thisWeek.periodEnd, "2027-01-17T19:00:00.000Z")

        let lastWeek = try build(selection, period: .lastWeek)
        XCTAssertEqual(lastWeek.counts, .init(wantsToUse: 0, deferred: 1, interrupted: 0))
        XCTAssertFalse(lastWeek.isPartial, "先週は確定した期間")
    }

    func testPurposesAndFeelingsDenominators() throws {
        record("2027-01-12 10:00", purpose: .contact, reflection: .satisfied)
        record("2027-01-12 11:00", purpose: .contact, reflection: .skipped)
        record("2027-01-12 12:00", purpose: nil, reflection: .wishedLess)
        record("2027-01-12 13:00", purpose: .change)
        var selection = ShareSelection(); selection.purposes = true; selection.feelings = true
        let payload = try build(selection)
        XCTAssertEqual(payload.purposes, .init(contact: 2, research: 0, break: 1, noReason: 0, unanswered: 1))
        // 「答えない」は回答に数えない。未回答は補完しない
        XCTAssertEqual(payload.feelings, .init(satisfied: 1, neutral: 0, wishedLess: 1))
    }

    func testUnselectedItemsAreNotEvenInTheJSON() throws {
        record("2027-01-12 10:00", purpose: .contact, reflection: .satisfied)
        var selection = ShareSelection(); selection.counts = true
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try build(selection))) as! [String: Any]
        XCTAssertNotNil(object["counts"])
        for key in ["purposes", "feelings", "phraseId", "recipientUids"] { XCTAssertNil(object[key], key) }
        XCTAssertEqual(object["showName"] as? Bool, true)
        // 個人の詳細は、どこにも含まれない
        let text = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
        for forbidden in ["id\":", "startedAt", "temporaryUnlockedApps", "token", "email"] { XCTAssertFalse(text.contains(forbidden), forbidden) }
    }

    // MARK: サーバーとの取り決め（両言語で同じ固定データを検証する）

    private func fixturePath(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("web/tests/fixtures/\(name)")
    }

    private func canonical(_ payload: SharePayload) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return String(data: try encoder.encode(payload), encoding: .utf8)! + "\n"
    }

    private func checkFixture(_ name: String, _ payload: SharePayload) throws {
        let url = fixturePath(name)
        guard FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) else { throw XCTSkip("web/ が見つからない環境") }
        let text = try canonical(payload)
        if ProcessInfo.processInfo.environment["UPDATE_FIXTURES"] == "1" {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text, "\(name) が、iOSの出力と食い違っている（UPDATE_FIXTURES=1 で再生成）")
    }

    func testFixturesShareThePayloadShapeWithTheServer() throws {
        record("2027-01-12 10:00", purpose: .contact, outcome: .wantsToUse, reflection: .satisfied)
        record("2027-01-12 11:00", purpose: .research, outcome: .deferred)
        var selection = ShareSelection(); selection.counts = true; selection.purposes = true; selection.feelings = true; selection.phrase = .p2
        try checkFixture("ios-web-share-payload.json", try build(selection))
        let friend = try ShareStatsBuilder.make(sessions: all(), mode: .device, period: .lastWeek, selection: selection, calendar: cal, now: jst("2027-01-13 20:00"),
                                                expiresInDays: nil, recipientUids: ["friend-uid-1"], idempotencyKey: "22222222-2222-4222-8222-222222222222")
        try checkFixture("ios-friend-share-payload.json", friend)
    }
}

// MARK: - APIクライアント

final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class APIClientTests: XCTestCase {
    private func makeClient(base: String? = "https://share.example.test", tokens: [String?] = ["TOKEN-1"]) -> (APIClient, () -> [Bool]) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        var forced: [Bool] = []
        var index = 0
        let client = APIClient(baseURL: base.flatMap(URL.init(string:)), session: URLSession(configuration: config)) { force in
            forced.append(force)
            defer { index += 1 }
            return tokens[min(index, tokens.count - 1)]
        }
        return (client, { forced })
    }

    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    func testAttachesBearerTokenAndDecodes() async throws {
        let (client, _) = makeClient()
        var seen: URLRequest?
        StubProtocol.handler = { request in seen = request; return (200, self.json(["uid": "u1", "displayName": "はなこ", "status": "active"])) }
        let me: MeResponse = try await client.send("GET", "/api/me")
        XCTAssertEqual(me.displayName, "はなこ")
        XCTAssertEqual(seen?.value(forHTTPHeaderField: "Authorization"), "Bearer TOKEN-1")
        XCTAssertEqual(seen?.url?.absoluteString, "https://share.example.test/api/me")
    }

    func testPublicCallsDoNotSendTheToken() async throws {
        let (client, forced) = makeClient()
        var seen: URLRequest?
        StubProtocol.handler = { request in seen = request; return (200, self.json(["inviterName": "アリス", "expiresAt": "2027-01-01T00:00:00Z"])) }
        let _: PublicInvitationResponse = try await client.send("GET", "/api/public/invitations/x", authenticated: false)
        XCTAssertNil(seen?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(forced().isEmpty, "未ログインの呼び出しで、トークンを取りに行かない")
    }

    func testRefreshesTheTokenOnceOn401() async throws {
        let (client, forced) = makeClient(tokens: ["OLD", "NEW"])
        var auths: [String] = []
        StubProtocol.handler = { request in
            auths.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            return auths.count == 1 ? (401, self.json(["error": "unauthorized"])) : (200, self.json(["uid": "u", "displayName": "x", "status": "active"]))
        }
        let _: MeResponse = try await client.send("GET", "/api/me")
        XCTAssertEqual(auths, ["Bearer OLD", "Bearer NEW"])
        XCTAssertEqual(forced(), [false, true], "2回目だけ、強制的に更新する")
    }

    func testGivesUpAfterASecond401() async {
        let (client, _) = makeClient(tokens: ["A", "B"])
        StubProtocol.handler = { _ in (401, self.json(["error": "unauthorized"])) }
        do { let _: MeResponse = try await client.send("GET", "/api/me"); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.kind, .unauthorized) }
    }

    func testSignedOutCallsAreUnauthorizedWithoutTouchingTheNetwork() async {
        let (client, _) = makeClient(tokens: [nil])
        StubProtocol.handler = { _ in XCTFail("通信してはいけない"); return (200, Data()) }
        do { let _: MeResponse = try await client.send("GET", "/api/me"); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.kind, .unauthorized) }
    }

    func testStatusMapping() async {
        let cases: [(Int, String, APIError.Kind)] = [
            (400, "invalid_request", .invalid), (403, "profile_required", .forbidden), (404, "unavailable", .notFound),
            (409, "conflict", .conflict), (410, "invitation_unavailable", .gone), (413, "payload_too_large", .invalid),
            (429, "daily_limit", .rateLimited), (503, "not_configured", .notConfigured), (500, "internal", .server),
        ]
        for (status, code, kind) in cases {
            let (client, _) = makeClient()
            StubProtocol.handler = { _ in (status, self.json(["error": code])) }
            do { let _: EmptyResponse = try await client.send("GET", "/x"); XCTFail("\(status)") }
            catch { XCTAssertEqual(error as? APIError, APIError(kind: kind, code: code), "\(status)") }
        }
    }

    func testOfflineAndNotConfigured() async {
        let (client, _) = makeClient()
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { let _: EmptyResponse = try await client.send("GET", "/x"); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.kind, .offline) }
        let (unconfigured, _) = makeClient(base: nil)
        do { let _: EmptyResponse = try await unconfigured.send("GET", "/x"); XCTFail() }
        catch { XCTAssertEqual((error as? APIError)?.kind, .notConfigured) }
    }

    func testErrorsNeverContainTheToken() async {
        let (client, _) = makeClient(tokens: ["SECRET-TOKEN"])
        StubProtocol.handler = { _ in (500, self.json(["error": "internal"])) }
        do { let _: EmptyResponse = try await client.send("GET", "/x"); XCTFail() }
        catch { XCTAssertFalse(String(describing: error).contains("SECRET-TOKEN")) }
    }

    func testPostBodyIsJSON() async throws {
        let (client, _) = makeClient()
        var body: [String: Any]?
        StubProtocol.handler = { request in
            let stream = request.httpBodyStream
            stream?.open()
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while let n = stream?.read(&buffer, maxLength: 1024), n > 0 { data.append(buffer, count: n) }
            body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (200, self.json(["uid": "u", "displayName": "なまえ", "status": "active"]))
        }
        struct Name: Encodable { var displayName: String }
        let _: MeResponse = try await client.send("PUT", "/api/me", body: Name(displayName: "なまえ"))
        XCTAssertEqual(body?["displayName"] as? String, "なまえ")
    }

    func testInitialDisplayNameIsTrimmedLimitedAndFallsBack() {
        XCTAssertEqual(DisplayName.initial(from: "  山田 太郎 "), "山田 太郎")
        XCTAssertEqual(DisplayName.initial(from: String(repeating: "あ", count: 30)).count, 20)
        XCTAssertEqual(DisplayName.initial(from: "a\nb\u{0}"), "ab")
        XCTAssertEqual(DisplayName.initial(from: nil), "ふと")
        XCTAssertEqual(DisplayName.initial(from: "   "), "ふと")
    }
}
