import AuthenticationServices
import CryptoKit
import Foundation
import Observation

/// 共有・フレンド機能の状態と操作。ログインは任意で、未設定・未ログイン・オフラインでも、個人の機能には影響しない。
/// サーバーが成功を返すまで、画面では「できた」と表示しない。
@MainActor
@Observable
final class SharingModel {
    enum Phase: Equatable { case idle, working }

    let config: Phase4Config
    let auth: AuthService
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let standingStore: StandingShareStoring
    private(set) var standingConfigs: [StandingShareConfig] = []
    @ObservationIgnored private let seenStore = SeenRecordsStore()
    /// フレンドから届いた記録の「見た」の控え
    private(set) var seen = SeenRecords()

    private(set) var phase: Phase = .idle
    private(set) var profile: MeResponse?
    private(set) var shares: [ShareListItem] = []
    private(set) var friends = FriendsResponse(friends: [], incoming: [], outgoing: [])
    private(set) var receivedShares: [ReceivedFriendShare] = []
    private(set) var sentShares: [SentFriendShare] = []
    private(set) var invitation: InvitationResponse?
    /// 直近の操作の結果（エラー文言）。成功は、各画面が状態の変化で示す
    var message: String?
    /// 招待リンクから開かれたときの、招待の識別子。確認の画面を出したら nil に戻す
    var pendingInviteToken: String?
    /// 作成直後の共有リンク（その場で見せるため。Keychainにも保存する）
    private(set) var lastCreatedURL: URL?

    init(config: Phase4Config = .load(), auth: AuthService? = nil, urlSession: URLSession = .shared, standingStore: StandingShareStoring = UserDefaultsStandingStore()) {
        self.config = config
        self.standingStore = standingStore
        let service = auth ?? AuthService(config: config, urlSession: urlSession, web: WebAuthRunner(), store: KeychainSessionStore(), driveStore: KeychainDriveTokenStore())
        self.auth = service
        self.api = APIClient(baseURL: config.apiBaseURL, session: urlSession) { [weak service] force in
            try await service?.validIDToken(forceRefresh: force)
        }
        // 開いた直後から、自分のアイコンを出す（サーバーの応答を待たない）
        if let uid = service.uid { seen = seenStore.load(uid: uid) }
        if let uid = service.uid, service.isSignedIn, let name = ProfileCache.name(uid: uid) {
            profile = MeResponse(uid: uid, displayName: name, status: "active")
        }
    }

    private func cacheProfile() {
        if let profile { ProfileCache.save(name: profile.displayName, uid: profile.uid) }
    }

    var isConfigured: Bool { config.isConfigured }
    var isSignedIn: Bool { auth.isSignedIn }
    var uid: String? { auth.uid }
    var isWorking: Bool { phase == .working }

    // MARK: ログイン

    func signIn() async {
        message = nil
        phase = .working
        defer { phase = .idle }
        do {
            // バックアップ用の許可も、同じ画面でお願いする（許可しなくても、ログインはできる）
            try await auth.signInWithGoogle(includeDrive: true)
            await loadProfile()
        } catch AuthError.cancelled {
            // 取りやめただけ。何も変えない
        } catch AuthError.notConfigured {
            message = tr("共有の設定がまだ終わっていません")
        } catch {
            message = tr("ログインできませんでした　もう一度お試しください")
        }
    }

    /// いまのアイコン（色を選んでいなければ、いまのテーマ色の番号）
    private static var currentAvatarSpec: AvatarSpec {
        AvatarSettings.shared.spec(themeIndex: ThemeColor.allCases.firstIndex(of: ThemeStore.shared.color) ?? 0)
    }

    /// いまのアカウントのログイン方法（Google / Apple）
    var signInProvider: SignInProvider? { auth.provider }

    @ObservationIgnored private var appleNonce: String?

    /// 「Appleで続ける」の要求を整える。求めるのは名前だけ（メールアドレスは求めない）。nonce は、ハッシュだけをAppleへ渡す。
    func prepareApple(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleNonce.make()
        appleNonce = nonce.raw
        request.requestedScopes = [.fullName]
        request.nonce = nonce.hashed
    }

    /// Appleでの認証が終わったとき。Firebaseのアカウントに替えて、プロフィールを読み込む。
    func completeApple(_ result: Result<ASAuthorization, Error>) async {
        message = nil
        switch result {
        case .failure(let error):
            // 取りやめただけなら、何も変えない
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            // Appleの認証そのものが失敗した（1000：設定・署名・iCloudのサインイン、1004：Appleの応答の失敗、など）
            let detail = AuthLog.describe(error)
            AuthLog.failure(stage: "apple.authorization", detail: detail)
            message = Self.loginFailedText(stage: "apple.authorization", detail: detail)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8),
                  let nonce = appleNonce else {
                let detail = "hasCredential=\(authorization.credential is ASAuthorizationAppleIDCredential) hasNonce=\(appleNonce != nil)"
                AuthLog.failure(stage: "apple.credential", detail: detail)
                message = Self.loginFailedText(stage: "apple.credential", detail: detail)
                return
            }
            AuthLog.info(stage: "apple.authorization.ok")
            phase = .working
            defer { phase = .idle }
            let name = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) }
            do {
                try await auth.signInWithApple(identityToken: token, rawNonce: nonce, fullName: name)
                appleNonce = nil
                await loadProfile()
                // アカウント削除のとき、Appleの接続も解除できるよう、サーバーに認可コードを預ける（できなくても、ログインには影響しない）
                if let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) {
                    let _: EmptyResponse? = try? await api.send("POST", "/api/apple/link", body: ["authorizationCode": code])
                }
            } catch AuthError.notConfigured {
                message = tr("共有の設定がまだ終わっていません")
            } catch {
                message = Self.loginFailedText(stage: "apple.firebase", detail: auth.lastFailureDetail ?? AuthLog.describe(error))
            }
        }
    }

    /// 「ログインできませんでした」。開発用のビルドでは、調べやすいよう、失敗した段階と種類（秘密を含まない）も添える。
    static func loginFailedText(stage: String, detail: String) -> String {
        let base = tr("ログインできませんでした　もう一度お試しください")
        #if DEBUG
        return base + "\n[\(stage)] \(detail)"
        #else
        return base
        #endif
    }

    func signOut() {
        if let uid { ProfileCache.clear(uid: uid); seenStore.clear(uid: uid) }
        auth.signOut()
        reset()
    }

    private func reset() {
        AvatarSettings.shared.reset()
        profile = nil; shares = []; friends = FriendsResponse(friends: [], incoming: [], outgoing: [])
        seen = SeenRecords(); receivedShares = []; sentShares = []; invitation = nil; lastCreatedURL = nil; message = nil; standingConfigs = []
    }

    func loadProfile() async {
        guard isSignedIn else { return }
        do {
            profile = try await api.send("GET", "/api/me")
            cacheProfile()
            await reconcileAvatar()
        } catch let error as APIError where error.kind == .notFound {
            // 初めてのログイン：Googleの名前を表示名の初期値にする（あとから変えられる）
            await createProfile()
        } catch { fail(error) }
    }

    /// アカウントの加入状況（Web で加入した分など）を、静かに取り直す。失敗しても、何も表示しない。
    func refreshAccountPlan() async {
        guard isSignedIn, profile != nil else { return }
        if let latest: MeResponse = try? await api.send("GET", "/api/me"), latest.webPlan != profile?.webPlan {
            profile = latest
            cacheProfile()
        }
    }

    private func createProfile() async {
        let name = DisplayName.initial(from: auth.providerDisplayName)
        do { profile = try await api.send("PUT", "/api/me", body: MeUpdate(displayName: name, avatar: Self.currentAvatarSpec)); cacheProfile() } catch { fail(error) }
    }

    /// サーバーのアイコンと、この端末のアイコンをそろえる。サーバーに無ければ送り、違っていれば、サーバーのものを取り込む。
    private func reconcileAvatar() async {
        guard let remote = profile?.avatar else { await syncAvatar(); return }
        if remote != Self.currentAvatarSpec { AvatarSettings.shared.adopt(remote) }
    }

    /// アイコンを変えたとき、フレンドにも見えるよう、サーバーへ送る。失敗しても、この端末の表示は変わらない。
    func syncAvatar() async {
        guard isSignedIn, let name = profile?.displayName else { return }
        if let updated: MeResponse = try? await api.send("PUT", "/api/me", body: MeUpdate(displayName: name, avatar: Self.currentAvatarSpec)) {
            profile = updated
            cacheProfile()
        }
    }

    func saveDisplayName(_ name: String) async -> Bool {
        phase = .working
        defer { phase = .idle }
        do {
            profile = try await api.send("PUT", "/api/me", body: MeUpdate(displayName: name, avatar: Self.currentAvatarSpec))
            cacheProfile()
            message = nil
            return true
        } catch { fail(error); return false }
    }

    // MARK: Web共有

    func previewPayload(sessions: [Session], mode: AppMode, period: SharePeriod, selection: ShareSelection, expiresInDays: Int?, recipientUids: [String]? = nil, key: String = UUID().uuidString.lowercased(), allowsMessage: Bool = false, events: [RestrictionEvent] = []) throws -> SharePayload {
        try ShareStatsBuilder.make(sessions: sessions, mode: mode, period: period, selection: selection, expiresInDays: expiresInDays, recipientUids: recipientUids, idempotencyKey: key, allowsMessage: allowsMessage,
                                        restrictionCounts: Self.restrictionCounts(events: events, mode: mode))
    }

    /// 制限の一時停止・終了の回数（期間内）。
    static func restrictionCounts(events: [RestrictionEvent], mode: AppMode) -> (DateInterval) -> RestrictionCounts {
        { interval in
            let c = RestrictionEventSummary.counts(events, mode: mode, interval: interval)
            return RestrictionCounts(pauses: c.pauses, ends: c.ends)
        }
    }

    /// 共有リンクを作る。サーバーが成功を返し、リンクを受け取れたときだけ、端末（Keychain）に保存する。
    func createWebShare(_ payload: SharePayload) async -> URL? {
        guard let uid else { message = tr("ログインが必要です"); return nil }
        phase = .working
        defer { phase = .idle }
        do {
            let created: CreatedShareResponse = try await api.send("POST", "/api/shares", body: payload)
            guard let urlString = created.url, let url = URL(string: urlString) else {
                // 再送で作成済みだった場合は、リンクを再取得できない。共有一覧から「リンクを作り直す」
                message = tr("共有は作成済みです　共有の一覧から、リンクを作り直せます")
                await loadShares()
                return nil
            }
            ShareLinkStore.save(url: urlString, uid: uid, shareId: created.shareId)
            lastCreatedURL = url
            message = nil
            await loadShares()
            return url
        } catch { fail(error); return nil }
    }

    func loadShares() async {
        guard isSignedIn else { return }
        do { shares = (try await api.send("GET", "/api/shares") as ShareListResponse).items } catch { fail(error) }
    }

    func localURL(for item: ShareListItem) -> URL? {
        uid.flatMap { ShareLinkStore.url(uid: $0, shareId: item.id) }
    }

    /// 停止は、サーバーが成功を返してから、一覧と端末のリンクを更新する。
    func revokeShare(_ item: ShareListItem) async {
        guard let uid else { return }
        phase = .working
        defer { phase = .idle }
        do {
            let _: EmptyResponse = try await api.send("DELETE", "/api/shares/\(item.id)")
            ShareLinkStore.remove(uid: uid, shareId: item.id)
            await loadShares()
        } catch { fail(error) }
    }

    /// 新しいリンクを作る。古いリンクは、サーバー側で無効になる。
    func rotateShare(_ item: ShareListItem) async -> URL? {
        guard let uid else { return nil }
        phase = .working
        defer { phase = .idle }
        do {
            let rotated: RotatedShareResponse = try await api.send("POST", "/api/shares/\(item.id)/rotate")
            guard let url = URL(string: rotated.url) else { throw APIError(kind: .server, code: "invalid_response") }
            ShareLinkStore.save(url: rotated.url, uid: uid, shareId: item.id)
            await loadShares()
            return url
        } catch { fail(error); return nil }
    }

    // MARK: フレンド

    func loadFriends() async {
        guard isSignedIn else { return }
        do { friends = try await api.send("GET", "/api/friends") } catch { fail(error) }
    }

    func createInvitation() async {
        phase = .working
        defer { phase = .idle }
        do { invitation = try await api.send("POST", "/api/invitations", body: ["idempotencyKey": UUID().uuidString.lowercased()]); message = nil } catch { fail(error) }
    }

    func cancelInvitation() async {
        guard let invitation else { return }
        do {
            let _: EmptyResponse = try await api.send("DELETE", "/api/invitations/\(invitation.inviteId)")
            self.invitation = nil
        } catch { fail(error) }
    }

    /// 招待リンクの、招待者の表示名（ログイン不要・統計は含まない）
    func previewInvitation(token: String) async -> PublicInvitationResponse? {
        do { return try await api.send("GET", "/api/public/invitations/\(token)", authenticated: false) } catch { fail(error); return nil }
    }

    /// 招待リンクまたはコードで、承認待ちのリクエストを送る。承認されるまで、統計は見えない。
    func sendFriendRequest(token: String? = nil, code: String? = nil) async -> Bool {
        phase = .working
        defer { phase = .idle }
        var body: [String: String] = [:]
        if let token { body["token"] = token }
        if let code { body["code"] = code }
        do {
            let _: FriendRequestResponse = try await api.send("POST", "/api/friend-requests", body: body)
            message = nil
            await loadFriends()
            return true
        } catch { fail(error); return false }
    }

    func respond(to request: FriendsResponse.Incoming, accept: Bool) async {
        phase = .working
        defer { phase = .idle }
        do {
            let _: EmptyResponse = try await api.send("POST", "/api/friend-requests/\(request.requestId)/\(accept ? "accept" : "decline")")
            await loadFriends()
        } catch { fail(error) }
    }

    func cancelRequest(_ request: FriendsResponse.Outgoing) async {
        do {
            let _: EmptyResponse = try await api.send("DELETE", "/api/friend-requests/\(request.requestId)")
            await loadFriends()
        } catch { fail(error) }
    }

    func removeFriend(_ friend: FriendsResponse.Friend) async {
        do {
            let _: EmptyResponse = try await api.send("DELETE", "/api/friends/\(friend.friendshipId)")
            await loadFriends()
        } catch { fail(error) }
    }

    func block(uid target: String) async {
        do {
            let _: EmptyResponse = try await api.send("POST", "/api/blocks/\(target)")
            await loadFriends()
        } catch { fail(error) }
    }

    // MARK: フレンド限定共有

    /// `standing` が true なら、継続共有にする（アプリを開いたときに更新する設定を、端末に保存する）。
    func createFriendShare(_ payload: SharePayload, standing: (period: SharePeriod, selection: ShareSelection)? = nil) async -> Bool {
        phase = .working
        defer { phase = .idle }
        do {
            let created: CreatedShareResponse = try await api.send("POST", "/api/friend-shares", body: payload)
            if let standing, let uid {
                var configs = standingStore.load(uid: uid)
                configs.removeAll { $0.shareId == created.shareId }
                configs.append(StandingShareConfig(shareId: created.shareId, period: standing.period, selection: standing.selection, refreshedAt: Date()))
                standingStore.save(configs, uid: uid)
                standingConfigs = configs
            }
            message = nil
            await loadFriendShares()
            return true
        } catch { fail(error); return false }
    }

    // MARK: 継続共有の更新

    func isStanding(_ shareId: String) -> StandingShareConfig? { standingConfigs.first { $0.shareId == shareId } }

    func loadStandingConfigs() {
        standingConfigs = uid.map { standingStore.load(uid: $0) } ?? []
    }

    /// アプリを開いたとき（一定時間ごと）・手動のときに、継続共有の統計を最新にする。失敗しても、個人の機能には影響しない。
    func refreshStanding(sessions: [Session], events: [RestrictionEvent] = [], mode: AppMode, force: Bool = false, now: Date = Date()) async {
        guard isSignedIn, mode == .device, let uid else { return }
        var configs = standingStore.load(uid: uid)
        guard !configs.isEmpty else { standingConfigs = []; return }
        var changed = false
        var lapsed = 0
        for index in configs.indices.reversed() where force || configs[index].isDue(now: now) {
            let config = configs[index]
            guard let payload = try? ShareStatsBuilder.make(sessions: sessions, mode: mode, period: config.sharePeriod, selection: config.selection, now: now, allowsMessage: true,
                                                            restrictionCounts: Self.restrictionCounts(events: events, mode: mode)) else { continue }
            do {
                let _: EmptyResponse = try await api.send("PUT", "/api/friend-shares/\(config.shareId)", body: payload.updateBody)
                configs[index].lastRefreshedAt = now
                changed = true
            } catch let error as APIError where error.kind == .gone || error.kind == .notFound {
                // 期限切れ・停止済み：更新を続けない
                configs.remove(at: index)
                changed = true
                lapsed += 1
            } catch let error as APIError where error.kind == .unauthorized || error.kind == .offline {
                break
            } catch { continue }
        }
        if changed { standingStore.save(configs, uid: uid) }
        standingConfigs = configs
        if lapsed > 0 { await loadFriendShares() }
        if force { await loadFriendShares() }
    }

    /// 新しい記録・更新が届いているか（バッジ用）。
    var hasUnseenRecords: Bool { receivedShares.contains { isUnseen($0) } }

    func isUnseen(_ item: ReceivedFriendShare) -> Bool {
        seen.isUnseen(id: item.id, version: item.updatedAt ?? item.createdAt)
    }

    /// 届いた記録を開いたとき。同じ版は、もう新しくない。
    func markSeen(id: String, version: String) {
        seen.markSeen(id: id, version: version)
        if let uid { seenStore.save(seen, uid: uid) }
    }

    /// 届いた記録の一覧だけを取り直す（アプリを開いたときなど。軽い確認）。
    func loadReceivedShares() async {
        guard isSignedIn else { return }
        if let uid { seen = seenStore.load(uid: uid) }
        if let list = try? await api.send("GET", "/api/friend-shares") as ReceivedFriendSharesResponse {
            receivedShares = list.items
            seen.prune(keeping: Set(list.items.map(\.id)))
            if let uid { seenStore.save(seen, uid: uid) }
        }
    }

    func loadFriendShares() async {
        guard isSignedIn else { return }
        do {
            receivedShares = (try await api.send("GET", "/api/friend-shares") as ReceivedFriendSharesResponse).items
            sentShares = (try await api.send("GET", "/api/friend-shares?role=sent") as SentFriendSharesResponse).items
        } catch { fail(error) }
    }

    func friendShareDetail(id: String) async -> FriendShareDetail? {
        do { return try await api.send("GET", "/api/friend-shares/\(id)") } catch { fail(error); return nil }
    }

    func revokeFriendShare(id: String) async {
        do {
            let _: EmptyResponse = try await api.send("DELETE", "/api/friend-shares/\(id)")
            if let uid {
                let remaining = standingStore.load(uid: uid).filter { $0.shareId != id }
                standingStore.save(remaining, uid: uid)
                standingConfigs = remaining
            }
            await loadFriendShares()
        } catch { fail(error) }
    }

    // MARK: アカウント削除

    /// アカウントを削除する。サーバーが「直近のログインの確認が要る」と返したときだけ、そのアカウントのログイン方法
    /// （Google または Apple）で、本人の確認をしてから、続ける。確認で別のアカウントが選ばれたら、何も変えずに止める。
    /// 途中で止まっても、もう一度押せば続きから進む。
    func deleteAccount() async -> Bool {
        guard let current = uid else { return false }
        phase = .working
        defer { phase = .idle }
        var reauthenticated = false
        do {
            for _ in 0..<6 {
                do {
                    let result: DeletionResponse = try await api.send("DELETE", "/api/me")
                    if result.status == "deleted" {
                        ProfileCache.clear(uid: current)
                        auth.signOut()
                        reset()
                        return true
                    }
                } catch let error as APIError where error.code == "recent_login_required" && !reauthenticated {
                    reauthenticated = true
                    try await reauthenticate(expecting: current)
                }
            }
            message = tr("削除が終わっていません　もう一度お試しください")
            return false
        } catch AuthError.cancelled {
            // 確認を取りやめた。ログインは、そのまま
            return false
        } catch AuthError.accountMismatch {
            message = tr("別のアカウントでログインされました　削除は行っていません")
            return false
        } catch AuthError.failed {
            message = Self.loginFailedText(stage: "reauth", detail: auth.lastFailureDetail ?? "")
            return false
        } catch { fail(error); return false }
    }

    /// 本人の確認。いまのアカウントを作ったログイン方法で行う（Appleのアカウントに、Googleは求めない）。
    private func reauthenticate(expecting uid: String) async throws {
        switch auth.provider ?? .google {
        case .google:
            try await auth.signInWithGoogle(expectingUID: uid)
        case .apple:
            let result = try await AppleAuthorizer().authorize()
            try await auth.signInWithApple(identityToken: result.identityToken, rawNonce: result.rawNonce, fullName: nil, expectingUID: uid)
            // 新しい認可コードを預け直す（削除のとき、Apple側の接続を取り消すため。できなくても、続ける）
            if let code = result.authorizationCode {
                let _: EmptyResponse? = try? await api.send("POST", "/api/apple/link", body: ["authorizationCode": code])
            }
        }
    }

    // MARK: エラー

    /// 失敗の表示。サーバー側のうまくいかなかった、といった、本人にできることのない失敗は、画面に出さない。
    private func fail(_ error: Error) {
        guard let api = error as? APIError, let text = Self.text(for: api) else { return }
        message = text
    }

    static func text(for error: APIError) -> String? {
        if error.code == "self_invite" { return tr("自分の招待は、受け入れられません") }
        switch error.kind {
        case .notConfigured: return tr("共有の設定がまだ終わっていません")
        case .offline: return tr("通信できませんでした　つながってから、もう一度お試しください")
        case .unauthorized: return tr("ログインの確認が必要です　もう一度ログインしてください")
        case .forbidden: return tr("この操作はできません")
        case .notFound: return tr("見つかりませんでした")
        case .gone: return tr("期限が切れているか、すでに使われています")
        case .conflict: return tr("同時に操作されました　もう一度お試しください")
        case .rateLimited: return tr("回数の上限です　しばらくしてからお試しください")
        case .invalid: return tr("入力を確認してください")
        case .server: return nil
        }
    }
}

extension SharingModel {
    /// 開かれたURLが招待リンクなら、確認の画面に渡す。統計の共有リンク（/s/…）は、アプリでは処理しない。
    func handleIncoming(url: URL) {
        if let token = InviteLink.token(from: url, allowedHost: config.allowedHost) { pendingInviteToken = token }
    }
}
