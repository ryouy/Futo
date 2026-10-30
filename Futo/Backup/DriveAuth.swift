import Foundation
import Observation

/// Google Driveの「アプリ専用領域」だけを使うための許可（`drive.appdata`）。
/// ログイン（Phase 4）とは別に、バックアップを有効にするときだけ、別の許可の画面を出す。
/// ほかのDriveのファイルは、見られない・触れない。トークンは、サーバーには送らない（端末のKeychainだけ）。
protocol DriveTokenStoring: AnyObject {
    func loadRefreshToken(uid: String) -> String?
    func saveRefreshToken(_ token: String, uid: String)
    func clear(uid: String)
}

final class KeychainDriveTokenStore: DriveTokenStoring {
    private func account(_ uid: String) -> String { "drive.refresh.\(uid)" }
    func loadRefreshToken(uid: String) -> String? {
        Keychain.get(account: account(uid)).flatMap { String(data: $0, encoding: .utf8) }
    }
    func saveRefreshToken(_ token: String, uid: String) { Keychain.set(Data(token.utf8), account: account(uid)) }
    func clear(uid: String) { Keychain.remove(account: account(uid)) }
}

enum DriveError: Error, Equatable {
    case notConfigured
    case cancelled
    /// 許可が取り消された・期限切れ。もう一度、許可が必要
    case needsConsent
    case offline
    case notFound
    case quota
    /// Google CloudでDrive APIが有効になっていない
    case apiDisabled
    case failed
}

@MainActor
@Observable
final class DriveAuthService {
    static let scope = "https://www.googleapis.com/auth/drive.appdata"

    @ObservationIgnored private let config: Phase4Config
    @ObservationIgnored private let urlSession: URLSession
    @ObservationIgnored private let web: WebAuthRunning
    @ObservationIgnored private let store: DriveTokenStoring
    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessExpiry = Date.distantPast

    /// このアカウントで、バックアップの許可を済ませているか
    private(set) var connectedUID: String?

    init(config: Phase4Config, urlSession: URLSession = .shared, web: WebAuthRunning, store: DriveTokenStoring) {
        self.config = config
        self.urlSession = urlSession
        self.web = web
        self.store = store
    }

    func refreshConnection(uid: String?) {
        connectedUID = uid.flatMap { store.loadRefreshToken(uid: $0) != nil ? $0 : nil }
    }

    /// 許可の画面を出して、アプリ専用領域の許可を得る。
    func connect(uid: String) async throws {
        guard config.isConfigured else { throw DriveError.notConfigured }
        let verifier = PKCE.randomString()
        let expectedState = PKCE.randomString(byteCount: 16)
        let redirect = "\(config.googleRedirectScheme):/oauth2redirect"
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: config.googleClientID),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: Self.scope),
            .init(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: expectedState),
        ]
        let callback: URL
        do {
            callback = try await web.run(url: components.url!, callbackScheme: config.googleRedirectScheme)
        } catch AuthError.cancelled {
            throw DriveError.cancelled
        } catch { throw DriveError.failed }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value else { throw DriveError.failed }

        let (status, body) = try await post("https://oauth2.googleapis.com/token", [
            "client_id": config.googleClientID, "code": code, "code_verifier": verifier,
            "grant_type": "authorization_code", "redirect_uri": redirect,
        ])
        guard status == 200, let access = body["access_token"] as? String, let refresh = body["refresh_token"] as? String else { throw DriveError.failed }
        // 許可された範囲に、アプリ専用領域が含まれていなければ、有効にしない
        let granted = (body["scope"] as? String ?? "").split(separator: " ").map(String.init)
        guard granted.contains(Self.scope) else { throw DriveError.needsConsent }
        accessToken = access
        accessExpiry = Date().addingTimeInterval(TimeInterval(body["expires_in"] as? Int ?? 3600))
        store.saveRefreshToken(refresh, uid: uid)
        connectedUID = uid
    }

    /// 有効なアクセストークン。期限が近ければ更新する。許可が失効していたら `needsConsent`。
    func accessToken(uid: String) async throws -> String {
        if let accessToken, accessExpiry.timeIntervalSinceNow > 60, connectedUID == uid { return accessToken }
        guard let refresh = store.loadRefreshToken(uid: uid) else { throw DriveError.needsConsent }
        let (status, body) = try await post("https://oauth2.googleapis.com/token", [
            "client_id": config.googleClientID, "refresh_token": refresh, "grant_type": "refresh_token",
        ])
        if status == 400 || status == 401 {
            store.clear(uid: uid); connectedUID = nil; accessToken = nil
            throw DriveError.needsConsent
        }
        guard status == 200, let token = body["access_token"] as? String else { throw DriveError.failed }
        accessToken = token
        accessExpiry = Date().addingTimeInterval(TimeInterval(body["expires_in"] as? Int ?? 3600))
        connectedUID = uid
        return token
    }

    /// 許可を取り消す（Google側でも失効させる）。Drive上のバックアップは、消さない。
    func disconnect(uid: String) async {
        if let refresh = store.loadRefreshToken(uid: uid) {
            _ = try? await post("https://oauth2.googleapis.com/revoke", ["token": refresh])
        }
        forget(uid: uid)
    }

    /// 端末から、許可の情報を除く（ログアウト・アカウント切替・削除のとき）
    func forget(uid: String) {
        store.clear(uid: uid)
        accessToken = nil
        if connectedUID == uid { connectedUID = nil }
    }

    private func post(_ url: String, _ fields: [String: String]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: url)!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .sorted().joined(separator: "&").data(using: .utf8)
        do {
            let (data, response) = try await urlSession.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return (status, (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:])
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code) {
            throw DriveError.offline
        } catch { throw DriveError.failed }
    }
}
