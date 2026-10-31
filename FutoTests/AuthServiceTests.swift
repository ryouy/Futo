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
            if url.contains("signInWithIdp") { return (200, self.json(["localId": uid, "idToken": "FB-ID-\(self.requests.count)", "refreshToken": "REFRESH-1", "expiresIn": expiresIn, "displayName": "山田 太郎"])) }
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
        XCTAssertEqual(store.saved, StoredAuthSession(uid: "uid-A", refreshToken: "REFRESH-1", provider: "google"))
        XCTAssertEqual(service.provider, .google)

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

    func testSignInWithApplePassesTheAppleTokenAndNonceToFirebaseAndRemembersTheProvider() async throws {
        installHappyNetwork(uid: "uid-APPLE")
        let store = MemoryStore()
        let service = make(store: store)
        let uid = try await service.signInWithApple(identityToken: "APPLE-ID-TOKEN", rawNonce: "RAW-NONCE", fullName: "  佐藤 花子 ")
        XCTAssertEqual(uid, "uid-APPLE")
        XCTAssertEqual(service.state, .signedIn(uid: "uid-APPLE"))
        XCTAssertEqual(service.provider, .apple)
        XCTAssertEqual(service.providerDisplayName, "佐藤 花子", "Appleが渡した名前を、表示名の初期値にする")
        XCTAssertEqual(store.saved, StoredAuthSession(uid: "uid-APPLE", refreshToken: "REFRESH-1", provider: "apple"))
        XCTAssertEqual(requests.count, 1, "Googleには、一切、通信しない")
        XCTAssertTrue(bodies[0].contains("providerId=apple.com"))
        XCTAssertTrue(bodies[0].contains("APPLE-ID-TOKEN"))
        XCTAssertTrue(bodies[0].contains("nonce=RAW-NONCE"))
        XCTAssertFalse(requests[0].url!.absoluteString.contains("google.com/o/oauth2"))
    }

    func testAppleSignInFailureIsAFailureAndStoresNothing() async {
        StubProtocol.handler = { _ in (400, Data("{}".utf8)) }
        let store = MemoryStore()
        let service = make(store: store)
        do { _ = try await service.signInWithApple(identityToken: "T", rawNonce: "N", fullName: nil); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .failed) }
        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(store.saved)
        XCTAssertNil(service.provider)
    }

    func testFirebaseFailureReasonIsRecordedWithoutAnyToken() async {
        StubProtocol.handler = { [unowned self] _ in (400, self.json(["error": ["code": 400, "message": "INVALID_IDP_RESPONSE : Unable to verify audience"]])) }
        let service = make()
        do { _ = try await service.signInWithApple(identityToken: "SECRET-APPLE-TOKEN", rawNonce: "SECRET-NONCE", fullName: nil); XCTFail() } catch {}
        let detail = service.lastFailureDetail ?? ""
        XCTAssertTrue(detail.contains("http=400"))
        XCTAssertTrue(detail.contains("INVALID_IDP_RESPONSE"))
        XCTAssertFalse(detail.contains("SECRET"), "トークンやnonceは、失敗の説明に入れない")
    }

    func testNeedConfirmationIsReportedAsAFailureNotASilentMerge() async {
        // Firebaseが「同じメールアドレスの別のアカウントがある」として、統合の確認を求めた（idTokenは返らない）
        StubProtocol.handler = { [unowned self] _ in (200, self.json(["needConfirmation": true, "providerId": "apple.com"])) }
        let store = MemoryStore()
        let service = make(store: store)
        do { _ = try await service.signInWithApple(identityToken: "T", rawNonce: "N", fullName: nil); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .failed) }
        XCTAssertTrue((service.lastFailureDetail ?? "").contains("needConfirmation=true"))
        XCTAssertEqual(service.state, .signedOut)
        XCTAssertNil(store.saved, "自動では統合しない")
    }

    final class FakeDriveStore: DriveTokenStoring {
        var tokens: [String: String] = [:]
        func loadRefreshToken(uid: String) -> String? { tokens[uid] }
        func saveRefreshToken(_ token: String, uid: String) { tokens[uid] = token }
        func clear(uid: String) { tokens[uid] = nil }
    }

    private func googleNetwork(scope: String, driveRefresh: String? = "DRIVE-REFRESH", uid: String = "uid-G") {
        StubProtocol.handler = { [unowned self] request in
            self.requests.append(request)
            self.bodies.append(self.body(of: request))
            let url = request.url!.absoluteString
            if url.contains("oauth2.googleapis.com/token") {
                var body: [String: Any] = ["id_token": "GOOGLE-ID-TOKEN", "scope": scope]
                if let driveRefresh { body["refresh_token"] = driveRefresh }
                return (200, self.json(body))
            }
            if url.contains("signInWithIdp") { return (200, self.json(["localId": uid, "idToken": "FB-ID", "refreshToken": "REFRESH-1", "expiresIn": "3600"])) }
            return (404, Data())
        }
    }

    func testGoogleSignInCanAskForBackupPermissionInTheSameScreenAndKeepsIt() async throws {
        googleNetwork(scope: "openid profile https://www.googleapis.com/auth/drive.appdata")
        let drive = FakeDriveStore()
        var authURL: URL?
        let service = AuthService(config: config, urlSession: session, web: FakeWeb { url in
            authURL = url
            let state = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
            return URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect?code=C&state=\(state)")!
        }, store: MemoryStore(), driveStore: drive)
        _ = try await service.signInWithGoogle(includeDrive: true)
        let scope = URLComponents(url: authURL!, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "scope" }!.value!
        XCTAssertEqual(scope, "openid profile https://www.googleapis.com/auth/drive.appdata")
        XCTAssertEqual(drive.tokens["uid-G"], "DRIVE-REFRESH", "許可されたら、バックアップ用の許可を控える")
    }

    func testBackupPermissionIsNotKeptWhenTheUserDidNotGrantIt() async throws {
        googleNetwork(scope: "openid profile")   // Driveの許可は、外された
        let drive = FakeDriveStore()
        let service = AuthService(config: config, urlSession: session, web: goodWeb(), store: MemoryStore(), driveStore: drive)
        _ = try await service.signInWithGoogle(includeDrive: true)
        XCTAssertTrue(drive.tokens.isEmpty, "許可されていなければ、控えない（ログインだけできる）")
    }

    func testPlainGoogleSignInNeverAsksForDrive() async throws {
        googleNetwork(scope: "openid profile https://www.googleapis.com/auth/drive.appdata")
        let drive = FakeDriveStore()
        let service = AuthService(config: config, urlSession: session, web: goodWeb(), store: MemoryStore(), driveStore: drive)
        _ = try await service.signInWithGoogle()
        XCTAssertTrue(drive.tokens.isEmpty)
    }

    func testReauthenticationWithAnotherAccountChangesNothing() async throws {
        installHappyNetwork(uid: "uid-A")
        let store = MemoryStore()
        let service = make(store: store)
        _ = try await service.signInWithGoogle()
        let before = store.saved
        // 確認のための再ログインで、別のアカウント（uid-B）が選ばれた
        installHappyNetwork(uid: "uid-B")
        do { _ = try await service.signInWithGoogle(expectingUID: "uid-A"); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .accountMismatch) }
        XCTAssertEqual(service.state, .signedIn(uid: "uid-A"), "別のアカウントに切り替わらない")
        XCTAssertEqual(store.saved, before)
        XCTAssertTrue(cleaned.isEmpty)
    }

    func testReauthenticationDoesNotFlashTheSignedOutState() async throws {
        installHappyNetwork(uid: "uid-A")
        let service = make()
        _ = try await service.signInWithGoogle()
        _ = try await service.signInWithGoogle(expectingUID: "uid-A")
        XCTAssertEqual(service.state, .signedIn(uid: "uid-A"))
    }

    func testAppleReauthenticationWithAnotherAccountChangesNothing() async throws {
        installHappyNetwork(uid: "uid-APPLE")
        let store = MemoryStore()
        let service = make(store: store)
        _ = try await service.signInWithApple(identityToken: "T", rawNonce: "N", fullName: nil)
        let before = store.saved
        installHappyNetwork(uid: "uid-OTHER")
        do { _ = try await service.signInWithApple(identityToken: "T2", rawNonce: "N2", fullName: nil, expectingUID: "uid-APPLE"); XCTFail() } catch { XCTAssertEqual(error as? AuthError, .accountMismatch) }
        XCTAssertEqual(service.state, .signedIn(uid: "uid-APPLE"))
        XCTAssertEqual(store.saved, before)
        XCTAssertEqual(service.provider, .apple)
    }

    func testSavedSessionWithoutAProviderIsTreatedAsGoogle() {
        let store = MemoryStore()
        store.saved = StoredAuthSession(uid: "old-user", refreshToken: "R")
        XCTAssertEqual(make(store: store).provider, .google, "以前の版で保存したログインは、Googleのもの")
        let decoded = try? JSONDecoder().decode(StoredAuthSession.self, from: Data(#"{"uid":"u","refreshToken":"r"}"#.utf8))
        XCTAssertEqual(decoded, StoredAuthSession(uid: "u", refreshToken: "r"))
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

    func testSignOutForgetsTheName() async throws {
        installHappyNetwork()
        let service = make()
        _ = try await service.signInWithGoogle()
        service.signOut()
        XCTAssertNil(service.providerDisplayName)
    }

    private func fakeJWT(_ claims: [String: Any]) -> String {
        func b64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        return b64(Data("{}".utf8)) + "." + b64(try! JSONSerialization.data(withJSONObject: claims)) + ".sig"
    }

    func testNameIsReadFromTheIDTokenWhenFirebaseOmitsIt() async throws {
        let jwt = fakeJWT(["name": "山田 太郎", "picture": "https://example.test/ignored.png"])
        StubProtocol.handler = { [unowned self] request in
            let url = request.url!.absoluteString
            if url.contains("oauth2.googleapis.com/token") { return (200, self.json(["id_token": jwt])) }
            if url.contains("signInWithIdp") { return (200, self.json(["localId": "uid-A", "idToken": "FB", "refreshToken": "R", "expiresIn": "3600"])) }
            return (404, Data())
        }
        let service = make(store: MemoryStore())
        _ = try await service.signInWithGoogle()
        XCTAssertEqual(service.providerDisplayName, "山田 太郎")
    }

    func testTokensWithoutANameOrMalformedOnesGiveNoName() {
        XCTAssertNil(GoogleIDToken.name(from: fakeJWT(["sub": "1"])))
        XCTAssertNil(GoogleIDToken.name(from: "not-a-jwt"))
        XCTAssertNil(GoogleIDToken.name(from: "a.%%%.c"))
    }
}
