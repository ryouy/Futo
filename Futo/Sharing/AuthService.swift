import Foundation
import Observation
import os

/// ブラウザ認証（ASWebAuthenticationSession）の窓口。テストでは差し替える。
protocol WebAuthRunning {
    /// ログインのページを開き、リダイレクト先のURL（`callbackScheme://…`）を返す。キャンセルは `AuthError.cancelled`
    func run(url: URL, callbackScheme: String) async throws -> URL
}

/// ログインの方法。どちらでログインしても、共有・フレンドは同じ機能を使える。
/// それぞれ別のアカウントになる（メールアドレスが同じでも、自動では統合しない）。
enum SignInProvider: String, Equatable {
    case google, apple
}

/// ログインの調査用のログ（Xcodeのコンソールや、Console.app で、subsystem: com.ryouy.futo / category: auth で絞れる）。
/// 出すのは、どの段階で・どの種類のエラーかだけ。トークン・認可コード・nonce・鍵・メールアドレスは、決して出さない。
enum AuthLog {
    private static let logger = Logger(subsystem: "com.ryouy.futo", category: "auth")

    static func failure(stage: String, detail: String) {
        logger.error("auth failed stage=\(stage, privacy: .public) \(detail, privacy: .public)")
    }

    static func info(stage: String, detail: String = "") {
        logger.info("auth stage=\(stage, privacy: .public) \(detail, privacy: .public)")
    }

    /// NSError の domain と code（内容は、秘密を含まない範囲の説明だけ）
    static func describe(_ error: Error) -> String {
        let ns = error as NSError
        return "domain=\(ns.domain) code=\(ns.code)"
    }
}

enum AuthError: Error, Equatable {
    case notConfigured
    case cancelled
    /// 確認のための再ログインで、別のアカウントが選ばれた（いまのアカウントは、変えない）
    case accountMismatch
    case failed          // 認証の失敗（通信・応答の不備）。理由の詳細や、トークンは含めない
}

/// 任意のログイン（Google または Apple）。Google（OAuth 2.0 + PKCE）またはAppleで得たIDトークンを、Firebase Authenticationへ渡す。
/// アプリの内部IDは、Firebase UID。Googleから使うのは名前だけで、表示名の初期値に使う（本人が変更できる）。メール・写真は使わない。
@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case signedOut
        case signingIn
        case signedIn(uid: String)
        /// 保存していたログインが失効した。共有操作だけが、再ログイン待ちになる（制限・待機は止めない）
        case needsReauth(uid: String)
    }

    private(set) var state: State = .signedOut
    /// 直近のログインで、Googleから受け取った名前。表示名の初期値にだけ使う（保存しない）
    private(set) var providerDisplayName: String?
    /// いまのアカウントのログイン方法
    private(set) var provider: SignInProvider?
    /// 直近のログインが失敗した理由の短い説明（トークンなどは含まない）。開発中の表示と、調査のためだけに使う
    private(set) var lastFailureDetail: String?

    @ObservationIgnored private let config: Phase4Config
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let web: WebAuthRunning
    @ObservationIgnored private let store: SessionStoring
    /// Googleのログインと同じ画面で、バックアップ（Drive）の許可も得たときの、許可の保管先
    @ObservationIgnored private let driveStore: DriveTokenStoring?
    @ObservationIgnored private var idToken: String?
    @ObservationIgnored private var idTokenExpiry = Date.distantPast
    @ObservationIgnored private var refreshToken: String?

    init(config: Phase4Config, urlSession: URLSession = .shared, web: WebAuthRunning, store: SessionStoring, driveStore: DriveTokenStoring? = nil) {
        self.driveStore = driveStore
        self.config = config
        self.urlSession = urlSession
        self.web = web
        self.store = store
        if let saved = store.load() {
            refreshToken = saved.refreshToken
            provider = SignInProvider(rawValue: saved.provider ?? "") ?? .google
            state = .signedIn(uid: saved.uid)
        }
    }

    var uid: String? {
        switch state {
        case .signedIn(let uid), .needsReauth(let uid): return uid
        case .signedOut, .signingIn: return nil
        }
    }

    var isSignedIn: Bool { if case .signedIn = state { return true } else { return false } }

    // MARK: ログイン

    /// Googleでログインする。成功したらFirebase UIDを返す。
    /// - `includeDrive`: 同じ許可の画面で、バックアップ用の許可（Driveのアプリ専用領域）も求める。許可されたら、あとで、もう一度尋ねない。
    /// - `expectingUID`: 確認のための再ログイン。別のアカウントが選ばれたら、いまのログインは変えずに `accountMismatch` で止める。
    @discardableResult
    func signInWithGoogle(includeDrive: Bool = false, expectingUID: String? = nil) async throws -> String {
        guard config.isConfigured else { throw AuthError.notConfigured }
        let previous = state
        // 再ログインの間は、「ログイン中」の表示に切り替えない（画面が、ログイン前の見た目に変わらないように）
        if expectingUID == nil { state = .signingIn }
        do {
            let verifier = PKCE.randomString()
            let expectedState = PKCE.randomString(byteCount: 16)
            let redirect = "\(config.googleRedirectScheme):/oauth2redirect"
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                .init(name: "client_id", value: config.googleClientID),
                .init(name: "redirect_uri", value: redirect),
                .init(name: "response_type", value: "code"),
                // ログインと、表示名の初期値（Googleの名前）に必要な最小限。Drive・メール・写真は求めない
                .init(name: "scope", value: includeDrive ? "openid profile \(DriveAuthService.scope)" : "openid profile"),
                .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: expectedState),
            ]
            let callback = try await web.run(url: components.url!, callbackScheme: config.googleRedirectScheme)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard items.first(where: { $0.name == "state" })?.value == expectedState,
                  let code = items.first(where: { $0.name == "code" })?.value else { throw AuthError.failed }

            let google = try await exchangeCode(code, verifier: verifier, redirect: redirect)
            let googleIDToken = google.idToken
            let firebase = try await signInToFirebase(postBody: "id_token=\(googleIDToken)&providerId=google.com", stage: "google.firebase")
            if let expectingUID, firebase.uid != expectingUID { throw AuthError.accountMismatch }
            // Firebaseの応答に名前が無いときは、GoogleのIDトークンの申告（name）から補う
            idToken = firebase.idToken
            idTokenExpiry = Date().addingTimeInterval(firebase.expiresIn)
            refreshToken = firebase.refreshToken
            providerDisplayName = firebase.displayName ?? GoogleIDToken.name(from: googleIDToken)
            // 別のアカウントに切り替わったら、前のアカウントの端末内の共有情報を除去する
            provider = .google
            store.save(StoredAuthSession(uid: firebase.uid, refreshToken: firebase.refreshToken, provider: SignInProvider.google.rawValue))
            // バックアップの許可も、同じ画面で得られていれば、ここで控える（許可の範囲に、Driveのアプリ専用領域が含まれるときだけ）
            if includeDrive, let driveStore, let driveRefresh = google.refreshToken,
               google.scope.split(separator: " ").contains(Substring(DriveAuthService.scope)) {
                driveStore.saveRefreshToken(driveRefresh, uid: firebase.uid)
            }
            state = .signedIn(uid: firebase.uid)
            return firebase.uid
        } catch {
            state = previous == .signingIn ? .signedOut : previous
            throw error as? AuthError ?? AuthError.failed
        }
    }

    /// Appleで続ける。Appleが発行したIDトークン（`rawNonce` のハッシュを含むもの）を、Firebase Authenticationへ渡す。
    /// 要求する情報は、名前だけ（メールアドレスは求めない）。名前は、Appleが最初の1回しか渡さないので、あれば表示名の初期値にする。
    @discardableResult
    func signInWithApple(identityToken: String, rawNonce: String, fullName: String?, expectingUID: String? = nil) async throws -> String {
        guard config.isConfigured else { throw AuthError.notConfigured }
        let previous = state
        if expectingUID == nil { state = .signingIn }
        do {
            lastFailureDetail = nil
            AuthLog.info(stage: "apple.firebase.request")
            let firebase = try await signInToFirebase(postBody: "id_token=\(identityToken)&providerId=apple.com&nonce=\(rawNonce)", stage: "apple.firebase")
            AuthLog.info(stage: "apple.firebase.ok")
            if let expectingUID, firebase.uid != expectingUID { throw AuthError.accountMismatch }
            idToken = firebase.idToken
            idTokenExpiry = Date().addingTimeInterval(firebase.expiresIn)
            refreshToken = firebase.refreshToken
            let name = fullName?.trimmingCharacters(in: .whitespacesAndNewlines)
            providerDisplayName = name?.isEmpty == false ? name : firebase.displayName
            provider = .apple
            store.save(StoredAuthSession(uid: firebase.uid, refreshToken: firebase.refreshToken, provider: SignInProvider.apple.rawValue))
            state = .signedIn(uid: firebase.uid)
            return firebase.uid
        } catch {
            if lastFailureDetail == nil { lastFailureDetail = AuthLog.describe(error) }
            state = previous == .signingIn ? .signedOut : previous
            throw error as? AuthError ?? AuthError.failed
        }
    }

    // MARK: IDトークン

    /// APIに付ける、有効なFirebase IDトークン。期限が近いか、`forceRefresh` なら更新する。ログインしていなければ nil。
    func validIDToken(forceRefresh: Bool = false) async throws -> String? {
        guard let refreshToken, uid != nil else { return nil }
        if !forceRefresh, let idToken, idTokenExpiry.timeIntervalSinceNow > 120 { return idToken }
        do {
            let refreshed = try await refresh(refreshToken)
            idToken = refreshed.idToken
            idTokenExpiry = Date().addingTimeInterval(refreshed.expiresIn)
            self.refreshToken = refreshed.refreshToken
            if let uid { store.save(StoredAuthSession(uid: uid, refreshToken: refreshed.refreshToken, provider: provider?.rawValue)) }
            if case .needsReauth(let uid) = state { state = .signedIn(uid: uid) }
            return refreshed.idToken
        } catch AuthError.cancelled {
            throw AuthError.cancelled
        } catch RefreshFailure.rejected {
            // 失効（パスワード変更・アカウント削除など）。共有操作だけを再ログイン待ちにする
            if let uid { state = .needsReauth(uid: uid) }
            return nil
        } catch {
            return nil // 通信できないだけ。ログイン状態は、そのまま
        }
    }

    // MARK: ログアウト

    /// ログアウト。サーバー上の共有は消えない（残る）。端末の認証状態を除く。
    /// 共有リンクの控え・継続共有の設定・バックアップの許可は、そのアカウントのものとして端末に残す
    /// （ログインし直したときに、リンクを失わないため）。アカウントの削除のときだけ、`clearLocalData` で、すべて除く。
    func signOut(clearLocalData: Bool = false) {
        if clearLocalData, let uid { ShareLinkCleanup.run(uid) }
        store.clear()
        providerDisplayName = nil
        provider = nil
        idToken = nil
        refreshToken = nil
        idTokenExpiry = .distantPast
        state = .signedOut
    }

    // MARK: 通信（Google・Firebaseの公開REST API）

    private enum RefreshFailure: Error { case rejected }

    private struct FirebaseTokens { var uid: String; var idToken: String; var refreshToken: String; var expiresIn: TimeInterval; var displayName: String? = nil }

    private func formRequest(_ url: URL, _ fields: [String: String]) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .sorted().joined(separator: "&").data(using: .utf8)
        return request
    }

    private func decode(_ request: URLRequest) async throws -> (Int, [String: Any]) {
        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (status, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        } catch {
            throw AuthError.failed
        }
    }

    private struct GoogleTokens { var idToken: String; var refreshToken: String?; var scope: String }

    private func exchangeCode(_ code: String, verifier: String, redirect: String) async throws -> GoogleTokens {
        let request = formRequest(URL(string: "https://oauth2.googleapis.com/token")!, [
            "code": code, "client_id": config.googleClientID, "code_verifier": verifier,
            "redirect_uri": redirect, "grant_type": "authorization_code",
        ])
        let (status, body) = try await decode(request)
        guard status == 200, let idToken = body["id_token"] as? String else { throw AuthError.failed }
        return GoogleTokens(idToken: idToken, refreshToken: body["refresh_token"] as? String, scope: body["scope"] as? String ?? "")
    }

    private func signInToFirebase(postBody: String, stage: String) async throws -> FirebaseTokens {
        var components = URLComponents(string: "https://identitytoolkit.googleapis.com/v1/accounts:signInWithIdp")!
        components.queryItems = [.init(name: "key", value: config.firebaseAPIKey)]
        var request = URLRequest(url: components.url!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "postBody": postBody,
            "requestUri": "http://localhost",
            "returnIdpCredential": true,
            "returnSecureToken": true,
        ])
        let (status, body) = try await decode(request)
        guard status == 200, let uid = body["localId"] as? String, let idToken = body["idToken"] as? String,
              let refresh = body["refreshToken"] as? String else {
            // 失敗の理由を、秘密を含まない形で控える（Firebaseが返すエラーの種類だけ）
            let detail = Self.firebaseFailureDetail(status: status, body: body)
            lastFailureDetail = detail
            AuthLog.failure(stage: stage, detail: detail)
            throw AuthError.failed
        }
        let name = (body["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return FirebaseTokens(uid: uid, idToken: idToken, refreshToken: refresh, expiresIn: TimeInterval(body["expiresIn"] as? String ?? "") ?? 3600, displayName: name?.isEmpty == false ? name : nil)
    }

    /// Firebase の応答から、失敗の種類だけを取り出す（例：`http=400 error=INVALID_IDP_RESPONSE`）。トークンや本文は、含めない。
    static func firebaseFailureDetail(status: Int, body: [String: Any]) -> String {
        if body["needConfirmation"] as? Bool == true {
            // 同じメールアドレスの別のアカウントがあり、Firebase が自動で統合しようとしている
            return "http=\(status) needConfirmation=true (same email already exists with another sign-in method)"
        }
        var parts = ["http=\(status)"]
        if let error = body["error"] as? [String: Any] {
            if let message = error["message"] as? String { parts.append("error=\(String(message.prefix(120)))") }
            if let code = error["code"] as? Int { parts.append("code=\(code)") }
        } else if status == 200 {
            parts.append("missing localId/idToken/refreshToken in response")
        }
        return parts.joined(separator: " ")
    }

    private func refresh(_ refreshToken: String) async throws -> FirebaseTokens {
        var components = URLComponents(string: "https://securetoken.googleapis.com/v1/token")!
        components.queryItems = [.init(name: "key", value: config.firebaseAPIKey)]
        let (status, body) = try await decode(formRequest(components.url!, ["grant_type": "refresh_token", "refresh_token": refreshToken]))
        if status == 400 || status == 401 { throw RefreshFailure.rejected }
        guard status == 200, let idToken = body["id_token"] as? String, let refresh = body["refresh_token"] as? String,
              let uid = body["user_id"] as? String else { throw AuthError.failed }
        return FirebaseTokens(uid: uid, idToken: idToken, refreshToken: refresh, expiresIn: TimeInterval(body["expires_in"] as? String ?? "") ?? 3600)
    }
}

/// ログアウト・アカウント切り替えのときに、そのアカウントの端末内の共有リンクを除去する窓口。
/// アプリではKeychainを消す。テストでは、呼ばれたことの記録に差し替えられる。
enum ShareLinkCleanup {
    nonisolated(unsafe) static var run: (String) -> Void = {
        ShareLinkStore.removeAll(uid: $0)
        UserDefaultsStandingStore().save([], uid: $0)
        // Driveの許可も、端末から除く（Drive上のバックアップは消えない）
        KeychainDriveTokenStore().clear(uid: $0)
    }
}


/// GoogleのIDトークン（JWT）の申告から、名前を読む。署名の検証はしない（表示名の初期値にだけ使い、認証には使わない）。
enum GoogleIDToken {
    static func name(from jwt: String) -> String? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let name = (object["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false ? name : nil
    }
}
