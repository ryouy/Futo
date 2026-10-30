import XCTest
@testable import Futo

final class MemoryDriveStore: DriveTokenStoring {
    var tokens: [String: String] = [:]
    func loadRefreshToken(uid: String) -> String? { tokens[uid] }
    func saveRefreshToken(_ token: String, uid: String) { tokens[uid] = token }
    func clear(uid: String) { tokens[uid] = nil }
}

final class DriveClientTests: XCTestCase {
    private var requests: [URLRequest] = []
    private var bodies: [Data] = []

    override func tearDown() { StubProtocol.handler = nil }

    private func client(token: String = "AT") -> DriveClient {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return DriveClient(session: URLSession(configuration: c)) { token }
    }

    private func bodyData(_ request: URLRequest) -> Data {
        if let b = request.httpBody { return b }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while case let n = stream.read(&buffer, maxLength: 4096), n > 0 { data.append(buffer, count: n) }
        return data
    }

    func testFindUsesOnlyTheAppDataFolderAndBearerToken() async throws {
        StubProtocol.handler = { [unowned self] r in
            self.requests.append(r)
            return (200, Data(#"{"files":[{"id":"F1","modifiedTime":"2026-10-30T10:00:00.000Z","size":"1234"}]}"#.utf8))
        }
        let file = try await client().find()
        XCTAssertEqual(file?.id, "F1")
        XCTAssertEqual(file?.size, 1234)
        XCTAssertNotNil(file?.modifiedTime)
        let url = requests[0].url!.absoluteString
        XCTAssertTrue(url.contains("spaces=appDataFolder"))
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer AT")
    }

    func testFindReturnsNilWhenThereIsNoBackup() async throws {
        StubProtocol.handler = { _ in (200, Data(#"{"files":[]}"#.utf8)) }
        let file = try await client().find()
        XCTAssertNil(file)
    }

    func testFirstSaveCreatesTheFileInsideAppDataFolder() async throws {
        StubProtocol.handler = { [unowned self] r in
            self.requests.append(r); self.bodies.append(self.bodyData(r))
            return (200, Data(#"{"id":"NEW"}"#.utf8))
        }
        let info = try await client().save(Data(#"{"hello":1}"#.utf8), existing: nil)
        XCTAssertEqual(info.id, "NEW")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertTrue(requests[0].url!.absoluteString.contains("uploadType=multipart"))
        let body = String(data: bodies[0], encoding: .utf8)!
        XCTAssertTrue(body.contains("\"parents\":[\"appDataFolder\"]"))
        XCTAssertTrue(body.contains("futo-backup.json"))
        XCTAssertTrue(body.contains(#"{"hello":1}"#))
    }

    func testLaterSavesOverwriteTheSameFile() async throws {
        StubProtocol.handler = { [unowned self] r in self.requests.append(r); return (200, Data(#"{"id":"F1"}"#.utf8)) }
        _ = try await client().save(Data("x".utf8), existing: DriveFileInfo(id: "F1"))
        XCTAssertEqual(requests[0].httpMethod, "PATCH")
        XCTAssertTrue(requests[0].url!.path.hasSuffix("/F1"))
    }

    func testErrorsAreClassifiedNotHiddenAsSuccess() async {
        func status(_ code: Int, _ body: String = "{}") async -> DriveError? {
            StubProtocol.handler = { _ in (code, Data(body.utf8)) }
            do { _ = try await client().find(); return nil } catch { return error as? DriveError }
        }
        let unauthorized = await status(401)
        let quota = await status(403, #"{"error":{"errors":[{"reason":"storageQuotaExceeded"}]}}"#)
        let disabled = await status(403, #"{"error":{"errors":[{"reason":"accessNotConfigured"}]}}"#)
        let missing = await status(404)
        XCTAssertEqual(unauthorized, .needsConsent)
        XCTAssertEqual(quota, .quota)
        XCTAssertEqual(disabled, .apiDisabled)
        XCTAssertEqual(missing, .notFound)
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await client().find(); XCTFail() } catch { XCTAssertEqual(error as? DriveError, .offline) }
    }
}

@MainActor
final class DriveAuthTests: XCTestCase {
    private let config = Phase4Config(plist: ["APIBaseURL": "https://share.example.test", "FirebaseAPIKey": "K", "GoogleClientID": "123-abc.apps.googleusercontent.com"])
    private var bodies: [String] = []

    override func tearDown() { StubProtocol.handler = nil }

    private var session: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    private func body(of request: URLRequest) -> String {
        guard let stream = request.httpBodyStream else { return String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 2048)
        while case let n = stream.read(&buffer, maxLength: 2048), n > 0 { data.append(buffer, count: n) }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func web(captured: @escaping (URL) -> Void = { _ in }) -> FakeWeb {
        FakeWeb { url in
            captured(url)
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=C&state=\(state)")!
        }
    }

    private func tokenResponse(scope: String = DriveAuthService.scope, refresh: Bool = true) -> (Int, Data) {
        var json: [String: Any] = ["access_token": "AT-1", "expires_in": 3600, "scope": scope]
        if refresh { json["refresh_token"] = "RT-1" }
        return (200, try! JSONSerialization.data(withJSONObject: json))
    }

    func testConnectAsksOnlyForTheAppDataScopeAndStoresTheRefreshToken() async throws {
        var authURL: URL?
        StubProtocol.handler = { [unowned self] r in self.bodies.append(self.body(of: r)); return self.tokenResponse() }
        let store = MemoryDriveStore()
        let service = DriveAuthService(config: config, urlSession: session, web: web { authURL = $0 }, store: store)
        try await service.connect(uid: "uid-A")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: authURL!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["scope"], "https://www.googleapis.com/auth/drive.appdata", "アプリ専用領域だけ。ほかのDriveは求めない")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(store.tokens["uid-A"], "RT-1")
        XCTAssertEqual(service.connectedUID, "uid-A")
        let token = try await service.accessToken(uid: "uid-A")
        XCTAssertEqual(token, "AT-1")
    }

    func testConnectFailsWhenTheScopeWasNotGranted() async {
        StubProtocol.handler = { [unowned self] _ in self.tokenResponse(scope: "openid") }
        let store = MemoryDriveStore()
        let service = DriveAuthService(config: config, urlSession: session, web: web(), store: store)
        do { try await service.connect(uid: "uid-A"); XCTFail() } catch { XCTAssertEqual(error as? DriveError, .needsConsent) }
        XCTAssertNil(store.tokens["uid-A"])
        XCTAssertNil(service.connectedUID)
    }

    func testCancelAndStateMismatch() async {
        let store = MemoryDriveStore()
        StubProtocol.handler = { _ in XCTFail("通信しない"); return (200, Data()) }
        let cancelled = DriveAuthService(config: config, urlSession: session, web: FakeWeb { _ in throw AuthError.cancelled }, store: store)
        do { try await cancelled.connect(uid: "u"); XCTFail() } catch { XCTAssertEqual(error as? DriveError, .cancelled) }
        let mismatch = DriveAuthService(config: config, urlSession: session, web: FakeWeb { _ in URL(string: "com.googleusercontent.apps.123-abc:/x?code=C&state=BAD")! }, store: store)
        do { try await mismatch.connect(uid: "u"); XCTFail() } catch { XCTAssertEqual(error as? DriveError, .failed) }
        XCTAssertTrue(store.tokens.isEmpty)
    }

    func testRevokedPermissionClearsTheStoredToken() async throws {
        let store = MemoryDriveStore()
        store.tokens["uid-A"] = "RT-OLD"
        StubProtocol.handler = { _ in (400, Data(#"{"error":"invalid_grant"}"#.utf8)) }
        let service = DriveAuthService(config: config, urlSession: session, web: web(), store: store)
        do { _ = try await service.accessToken(uid: "uid-A"); XCTFail() } catch { XCTAssertEqual(error as? DriveError, .needsConsent) }
        XCTAssertNil(store.tokens["uid-A"])
    }

    func testDisconnectRevokesAtGoogleAndForgetsLocally() async {
        let store = MemoryDriveStore()
        store.tokens["uid-A"] = "RT-1"
        var urls: [String] = []
        StubProtocol.handler = { r in urls.append(r.url!.absoluteString); return (200, Data("{}".utf8)) }
        let service = DriveAuthService(config: config, urlSession: session, web: web(), store: store)
        service.refreshConnection(uid: "uid-A")
        XCTAssertEqual(service.connectedUID, "uid-A")
        await service.disconnect(uid: "uid-A")
        XCTAssertTrue(urls.contains { $0.contains("oauth2.googleapis.com/revoke") })
        XCTAssertNil(store.tokens["uid-A"])
        XCTAssertNil(service.connectedUID)
    }

    func testNotConfiguredNeverTouchesTheNetwork() async {
        StubProtocol.handler = { _ in XCTFail("通信しない"); return (200, Data()) }
        let service = DriveAuthService(config: .empty, urlSession: session, web: web(), store: MemoryDriveStore())
        do { try await service.connect(uid: "u"); XCTFail() } catch { XCTAssertEqual(error as? DriveError, .notConfigured) }
    }
}
