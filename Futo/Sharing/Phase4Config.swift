import Foundation

/// 共有・フレンド機能の接続先。値は `Phase4Config.plist`（公開してよいクライアント設定だけ）に入れる。
/// 空のままなら「未設定」として扱い、共有機能は使えない（個人の機能は、そのまま使える）。
/// サーバーの秘密鍵（Firebase Adminなど）は、ここにもアプリにも入れない。
struct Phase4Config: Equatable {
    /// 共有サーバーの土台のURL（例：https://futo-share.example.com）
    var apiBaseURL: URL?
    /// Firebaseの「ウェブAPIキー」（公開してよいクライアント用のキー）
    var firebaseAPIKey: String
    /// Google OAuthの、iOS用クライアントID（例：123-abc.apps.googleusercontent.com）
    var googleClientID: String

    var isConfigured: Bool {
        apiBaseURL != nil && !firebaseAPIKey.isEmpty && !googleClientID.isEmpty
    }

    /// 共有・招待リンクとして受け付ける、サーバーのホスト名。
    var allowedHost: String? { apiBaseURL?.host }

    /// Googleのリダイレクト用スキーム（クライアントIDを逆順にしたもの）。
    var googleRedirectScheme: String {
        let prefix = googleClientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    static let empty = Phase4Config(apiBaseURL: nil, firebaseAPIKey: "", googleClientID: "")

    init(apiBaseURL: URL?, firebaseAPIKey: String, googleClientID: String) {
        self.apiBaseURL = apiBaseURL
        self.firebaseAPIKey = firebaseAPIKey
        self.googleClientID = googleClientID
    }

    init(plist: [String: Any]) {
        let base = (plist["APIBaseURL"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // 共有・招待のデータを送る先は、必ずHTTPS
        let url = URL(string: base).flatMap { $0.scheme == "https" && $0.host != nil ? $0 : nil }
        self.init(
            apiBaseURL: url,
            firebaseAPIKey: (plist["FirebaseAPIKey"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            googleClientID: (plist["GoogleClientID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }

    static func load(bundle: Bundle = .main) -> Phase4Config {
        guard let url = bundle.url(forResource: "Phase4Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return .empty }
        return Phase4Config(plist: plist)
    }
}
