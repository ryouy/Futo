import XCTest
@testable import Futo

final class MemoryStore: SessionStoring {
    var saved: StoredAuthSession?
    func load() -> StoredAuthSession? { saved }
    func save(_ session: StoredAuthSession) { saved = session }
    func clear() { saved = nil }
}

struct FakeWeb: WebAuthRunning {
    /// 認証ページのURLを受け取り、リダイレクト先のURL（または失敗）を返す
    var respond: (URL) throws -> URL
    func run(url: URL, callbackScheme: String) async throws -> URL { try respond(url) }
}

@MainActor
final class AuthServiceTests: XCTestCase {
    private let config = Phase4Config(plist: ["APIBaseURL": "https://share.example.test", "FirebaseAPIKey": "API-KEY", "GoogleClientID": "123-abc.apps.googleusercontent.com"])
    private var requests: [URLRequest] = []
    private var bodies: [String] = []
    private var cleaned: [String] = []

    override func setUp() {
        requests = []; bodies = []; cleaned = []
        ShareLinkCleanup.run = { [unowned self] in self.cleaned.append($0) }
    }

    override func tearDown() {
        ShareLinkCleanup.run = { ShareLinkStore.removeAll(uid: $0) }
        StubProtocol.handler = nil
    }

    private var session: URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: c)
    }

    private func body(of request: URLRequest) -> String {
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 2048)
        while case let n = stream.read(&buffer, maxLength: 2048), n > 0 { data.append(buffer, count: n) }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    /// 正しいリダイレクトを返すWeb認証（stateを引き継ぐ）
    private func goodWeb(code: String = "AUTH-CODE") -> FakeWeb {
        FakeWeb { url in
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=\(code)&state=\(state)")!
        }
    }

    /// Google→Firebaseの、正常な応答
    private func installHappyNetwork(uid: String = "uid-A", expiresIn: String = "3600") {
        StubProtocol.handler = { [unowned self] request in
            self.requests.append(request)
            self.bodies.append(self.body(of: request))
            let url = request.url!.absoluteString
            if url.contains("oauth2.googleapis.com/token") { return (200, self.json(["id_token": "GOOGLE-ID-TOKEN"])) }
            if url.contains("signInWithIdp") { return (200, self.json(["localId": uid, "idToken": "FB-ID-\(self.requests.count)", "refreshToken": "REFRESH-1", "expiresIn": expiresIn, "displayName": "山田 太郎", "photoUrl": "https://lh3.googleusercontent.com/a/abc=s96-c"])) }
            if url.contains("securetoken.googleapis.com") { return (200, self.json(["id_token": "FB-REFRESHED", "refresh_token": "REFRESH-2", "user_id": uid, "expires_in": "3600"])) }
            return (404, Data())
        }
    }

    private func make(web: FakeWeb? = nil, store: MemoryStore = MemoryStore(), config: Phase4Config? = nil) -> AuthService {
        AuthService(config: config ?? self.config, urlSession: session, web: web ?? goodWeb(), store: store)
    }

    func testSuccessfulSignInUsesPKCEWithMinimalScopeAndStoresOnlyTheRefreshToken() async throws {
        installHappyNetwork()
        var authURL: URL?
        let store = MemoryStore()
        let service = make(web: FakeWeb { url in
            authURL = url
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=AUTH-CODE&state=\(state)")!
        }, store: store)
        let uid = try await service.signInWithGoogle()
        XCTAssertEqual(uid, "uid-A")
        XCTAssertEqual(service.state, .signedIn(uid: "uid-A"))
        XCTAssertEqual(service.providerDisplayName, "山田 太郎")
        XCTAssertEqual(service.photoURL?.host, "lh3.googleusercontent.com")
        XCTAssertEqual(store.saved, StoredAuthSession(uid: "uid-A", refreshToken: "REFRESH-1", photoURL: "https://lh3.googleusercontent.com/a/abc=s96-c"))

        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: authURL!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["scope"], "openid profile", "名前（表示名の初期値）までで、Drive・メール・写真は求めない")
        XCTAssertEqual(items["code_challenge_method"], "S256")
        XCTAssertEqual(items["client_id"], "123-abc.apps.googleusercontent.com")
        XCTAssertEqual(items["response_type"], "code")
        let challenge = items["code_challenge"]!
        // コード交換では、同じ検証用の乱数を送る（そのハッシュが、認証ページに渡したものと一致する）
        let exchange = bodies[0]
        let verifier = exchange.split(separator: "&").first { $0.hasPrefix("code_verifier=") }!.dropFirst("code_verifier=".count)
        XCTAssertEqual(PKCE.challenge(for: String(verifier)), challenge)
        XCTAssertTrue(exchange.contains("grant_type=authorization_code"))
        XCTAssertTrue(exchange.contains("code=AUTH-CODE"))
        // Firebaseへは、GoogleのIDトークンを渡す（アクセストークンではない）
        XCTAssertTrue(bodies[1].contains("providerId=google.com"))
        XCTAssertTrue(bodies[1].contains("GOOGLE-ID-TOKEN"))
        XCTAssertTrue(requests[1].url!.absoluteString.contains("key=API-KEY"))
    }

    func testStateMismatchIsRejectedAndNothingIsStored() async {
        installHappyNetwork()
        let store = MemoryStore()
        let service = make(web: FakeWeb { _ in URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=X&state=WRONG")! }, store: store)
        do { _ = try await service.signInWithGoogle(); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .failed) }
        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(store.saved)
        XCTAssertTrue(requests.isEmpty, "stateが合わないときは、通信しない")
    }

    func testCancelLeavesPersonalFeaturesAndStateUntouched() async {
        installHappyNetwork()
        let service = make(web: FakeWeb { _ in throw AuthError.cancelled })
        do { _ = try await service.signInWithGoogle(); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .cancelled) }
        XCTAssertEqual(service.state, .signedOut)
    }

    func testFailedExchangeIsAFailureNotASuccess() async {
        StubProtocol.handler = { _ in (400, Data("{}".utf8)) }
        let service = make()
        do { _ = try await service.signInWithGoogle(); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .failed) }
        XCTAssertEqual(service.state, .signedOut)
    }

    func testNotConfiguredNeverTouchesTheNetwork() async {
        StubProtocol.handler = { _ in XCTFail("通信してはいけない"); return (200, Data()) }
        let service = make(config: .empty)
        do { _ = try await service.signInWithGoogle(); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .notConfigured) }
    }

    func testTokenIsCachedThenRefreshedNearExpiry() async throws {
        installHappyNetwork(expiresIn: "3600")
        let service = make()
        _ = try await service.signInWithGoogle()
        let count = requests.count
        let cached = try await service.validIDToken()
        XCTAssertEqual(cached, "FB-ID-2")
        XCTAssertEqual(requests.count, count, "有効なうちは、通信しない")
        let refreshed = try await service.validIDToken(forceRefresh: true)
        XCTAssertEqual(refreshed, "FB-REFRESHED")
        XCTAssertTrue(requests.last!.url!.absoluteString.contains("securetoken"))
    }

    func testTokenWithLittleTimeLeftIsRefreshed() async throws {
        installHappyNetwork(expiresIn: "60")
        let service = make()
        _ = try await service.signInWithGoogle()
        let t = try await service.validIDToken()
        XCTAssertEqual(t, "FB-REFRESHED")
    }

    func testRevokedSessionOnlyBlocksSharing() async throws {
        installHappyNetwork(expiresIn: "60")
        let service = make()
        _ = try await service.signInWithGoogle()
        StubProtocol.handler = { _ in (400, Data("{\"error\":{\"message\":\"TOKEN_EXPIRED\"}}".utf8)) }
        let t = try await service.validIDToken()
        XCTAssertNil(t, "失効していたら、トークンを返さない")
        XCTAssertEqual(service.state, .needsReauth(uid: "uid-A"))
        XCTAssertEqual(service.uid, "uid-A")
    }

    func testOfflineRefreshKeepsTheSignedInState() async throws {
        installHappyNetwork(expiresIn: "60")
        let service = make()
        _ = try await service.signInWithGoogle()
        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let t = try await service.validIDToken()
        XCTAssertNil(t)
        XCTAssertEqual(service.state, .signedIn(uid: "uid-A"), "通信できないだけでは、ログアウト扱いにしない")
    }

    func testSignedOutHasNoToken() async throws {
        let t = try await make().validIDToken()
        XCTAssertNil(t)
    }

    func testSavedSessionRestoresWithoutNetwork() async throws {
        StubProtocol.handler = { _ in XCTFail("起動時に通信してはいけない"); return (200, Data()) }
        let store = MemoryStore()
        store.saved = StoredAuthSession(uid: "uid-A", refreshToken: "R")
        XCTAssertEqual(make(store: store).state, .signedIn(uid: "uid-A"))
    }

    func testSignOutRemovesAuthStateAndThatAccountsLocalShareData() async throws {
        installHappyNetwork()
        let store = MemoryStore()
        let service = make(store: store)
        _ = try await service.signInWithGoogle()
        service.signOut()
        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(store.saved)
        XCTAssertEqual(cleaned, ["uid-A"])
        let t = try await service.validIDToken()
        XCTAssertNil(t)
    }

    func testSwitchingAccountsCleansTheOldAccountsLocalData() async throws {
        installHappyNetwork(uid: "uid-A")
        let service = make()
        _ = try await service.signInWithGoogle()
        installHappyNetwork(uid: "uid-B")
        _ = try await service.signInWithGoogle()
        XCTAssertEqual(cleaned, ["uid-A"], "別アカウントになったら、前のアカウントの端末内の共有情報を除去する")
        XCTAssertEqual(service.uid, "uid-B")
    }

    func testOnlyGoogleHTTPSPhotosAreAccepted() {
        XCTAssertNotNil(AuthService.trustedPhotoURL("https://lh3.googleusercontent.com/a/x=s96-c"))
        XCTAssertNil(AuthService.trustedPhotoURL("http://lh3.googleusercontent.com/a/x"))
        XCTAssertNil(AuthService.trustedPhotoURL("https://evil.example.com/a.png"))
        XCTAssertNil(AuthService.trustedPhotoURL("https://googleusercontent.com.evil.com/a.png"))
        XCTAssertNil(AuthService.trustedPhotoURL(nil))
    }

    func testSignOutForgetsThePhotoAndName() async throws {
        installHappyNetwork()
        let service = make()
        _ = try await service.signInWithGoogle()
        service.signOut()
        XCTAssertNil(service.photoURL)
        XCTAssertNil(service.providerDisplayName)
    }
}
