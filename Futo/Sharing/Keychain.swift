import Foundation
import Security

/// Keychainの薄い包み。この端末だけに保存し、iCloudには同期しない。
enum Keychain {
    private static let service = "jp.futo.sharing"

    private static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func set(_ data: Data, account: String) {
        var query = base(account)
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(account: String) -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func remove(account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    /// 指定の接頭辞で始まる項目を、すべて消す（ログアウトで、そのアカウントの分だけを除去する）。
    static func removeAll(prefix: String) {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnAttributes as String: true, kSecMatchLimit as String: kSecMatchLimitAll]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        query = [:]
        for item in items {
            if let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(prefix) { remove(account: account) }
        }
    }
}

/// ログイン情報の保存先。アプリではKeychain、テストではメモリ。
protocol SessionStoring: AnyObject {
    func load() -> StoredAuthSession?
    func save(_ session: StoredAuthSession)
    func clear()
}

struct StoredAuthSession: Codable, Equatable {
    var uid: String
    var refreshToken: String
    /// ログインに使ったもの（"google" / "apple"）。以前の版で保存した分は nil（Google）
    var provider: String? = nil
}

final class KeychainSessionStore: SessionStoring {
    private let account = "auth.session"
    func load() -> StoredAuthSession? {
        Keychain.get(account: account).flatMap { try? JSONDecoder().decode(StoredAuthSession.self, from: $0) }
    }
    func save(_ session: StoredAuthSession) {
        if let data = try? JSONEncoder().encode(session) { Keychain.set(data, account: account) }
    }
    func clear() { Keychain.remove(account: account) }
}

/// 作成した共有リンク（生トークンを含むURL）の保管。UID別にKeychainへ。
/// リンクを再表示するためだけに持つ。別の端末では復元できないので、その場合は再発行を案内する。
enum ShareLinkStore {
    private static func account(uid: String, shareId: String) -> String { "share.\(uid).\(shareId)" }

    static func save(url: String, uid: String, shareId: String) {
        Keychain.set(Data(url.utf8), account: account(uid: uid, shareId: shareId))
    }

    static func url(uid: String, shareId: String) -> URL? {
        Keychain.get(account: account(uid: uid, shareId: shareId)).flatMap { String(data: $0, encoding: .utf8) }.flatMap(URL.init(string:))
    }

    static func remove(uid: String, shareId: String) {
        Keychain.remove(account: account(uid: uid, shareId: shareId))
    }

    /// ログアウト・アカウント削除で、そのアカウントの分を、すべて除去する。
    static func removeAll(uid: String) {
        Keychain.removeAll(prefix: "share.\(uid).")
    }
}
