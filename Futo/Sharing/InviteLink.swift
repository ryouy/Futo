import Foundation

/// フレンド招待のリンク（`https://<共有ドメイン>/i/<token>`）の解釈。
/// 許可したホストとパスだけを処理する。統計共有のリンク（`/s/…`）は、アプリでは処理しない（Web閲覧のまま）。
enum InviteLink {
    static func token(from url: URL, allowedHost: String?) -> String? {
        guard let allowedHost, url.scheme == "https", url.host?.lowercased() == allowedHost.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, parts[0] == "i", isToken(parts[1]) else { return nil }
        return parts[1]
    }

    /// 32バイトの乱数のbase64url（43文字）。
    static func isToken(_ value: String) -> Bool {
        value.count == 43 && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    private static let codeAlphabet = Set("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    /// 入力された招待コードを、大文字・区切りなしの12文字にそろえる。形式が違えば nil。
    static func normalizedCode(_ input: String) -> String? {
        let cleaned = input.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard cleaned.count == 12, cleaned.allSatisfy({ codeAlphabet.contains($0) }) else { return nil }
        return cleaned
    }
}
