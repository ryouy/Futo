import CryptoKit
import Foundation

extension Data {
    /// URLに使える、`=` なしのBase64。
    var base64URLString: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Googleログイン（OAuth 2.0 + PKCE）で使う、検証用の乱数と、そのハッシュ。
enum PKCE {
    static func randomString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
        precondition(status == errSecSuccess, "乱数を作れませんでした")
        return Data(bytes).base64URLString
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString
    }
}
