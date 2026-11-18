import Foundation
import UIKit

/// シールド（制限中のアプリを開いたときにOSが出す画面）の色。本体がテーマから決めて、App Groupに置き、拡張（FutoShield）が読む。
/// 値は（ライト, ダーク）の「0xRRGGBB」。読めない・まだ無いときは、既定の緑（`fallback`）。
struct ShieldTheme: Codable, Equatable, Hashable {
    var background: [UInt32]
    var title: [UInt32]
    var body: [UInt32]
    var buttonBackground: [UInt32]
    var buttonText: [UInt32]
    /// ロゴを載せる角丸の台の色
    var tile: UInt32

    static let key = "device.shieldTheme"

    /// 以前からの、深緑の見た目
    static let fallback = ShieldTheme(
        background: [0xFCF8F0, 0x10312C], title: [0x124A42, 0xFCF8F0], body: [0x4F5F5A, 0xD9D4C8],
        buttonBackground: [0x196459, 0xFCF8F0], buttonText: [0xFCF8F0, 0x124A42], tile: 0x196459)

    /// アプリのテーマ（アクセントと地の色）から作る。ボタンの文字は、アクセントの上に載せる生成り色（アクセントは、これが読める濃さ）。
    static func make(accent: UInt32, textAccent: (UInt32, UInt32), backgroundTop: (UInt32, UInt32)) -> ShieldTheme {
        ShieldTheme(
            background: [backgroundTop.0, backgroundTop.1],
            title: [textAccent.0, 0xEEE9DF],
            body: [0x4F5F5A, 0xD9D4C8],
            buttonBackground: [accent, accent],
            buttonText: [0xFFFEFA, 0xFFFEFA],
            tile: accent)
    }

    /// 本体と拡張で共有するApp Group（本体は "group.<bundle id>"、拡張は末尾の名前を除いた同じ値）
    static var groupID: String {
        var id = Bundle.main.bundleIdentifier ?? ""
        for suffix in [".shieldaction", ".shield", ".monitor"] where id.hasSuffix(suffix) { id.removeLast(suffix.count); break }
        return "group." + id
    }

    static func load(from defaults: UserDefaults? = UserDefaults(suiteName: groupID)) -> ShieldTheme {
        guard let data = defaults?.data(forKey: key), let theme = try? JSONDecoder().decode(ShieldTheme.self, from: data),
              theme.isValid else { return .fallback }
        return theme
    }

    func save(to defaults: UserDefaults? = UserDefaults(suiteName: ShieldTheme.groupID)) {
        guard let defaults, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// 配列の長さが（ライト, ダーク）の2つあるか（壊れた値で落ちないように）
    var isValid: Bool {
        [background, title, body, buttonBackground, buttonText].allSatisfy { $0.count == 2 }
    }

    static func uiColor(_ pair: [UInt32]) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? pair[1] : pair[0]
            return color(hex)
        }
    }

    static func color(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
