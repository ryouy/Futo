import ManagedSettings
import ManagedSettingsUI
import UIKit

/// 制限されたアプリ・サイトを開いたときに、OSが表示する画面（シールド）の見た目。
///
/// 変えられるのは、OSが用意した範囲（背景色・アイコン・タイトル・説明・ボタンの文言と色）だけ。
/// 自由なSwiftUI画面や待機タイマーは置けない。フォントなどはOSが決める。
/// ボタンは、実際にできる動作（`ShieldActionResponse.close` = ホームに戻る）と一致させる。
/// 本体アプリを直接開くAPIは、公式には用意されていないため、ボタンにはしない（説明文で案内する）。
final class FutoShieldConfiguration: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration { Self.make() }
    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration { Self.make() }
    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration { Self.make() }
    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration { Self.make() }

    // MARK: 色（生成りと、落ち着いた緑。ダークでは、深い緑地に生成り）

    private static func color(light: UInt32, dark: UInt32) -> UIColor {
        UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    private static let background = color(light: 0xFCF8F0, dark: 0x10312C)
    private static let titleColor = color(light: 0x124A42, dark: 0xFCF8F0)
    private static let bodyColor = color(light: 0x4F5F5A, dark: 0xD9D4C8)
    private static let buttonBackground = color(light: 0x196459, dark: 0xFCF8F0)
    private static let buttonText = color(light: 0xFCF8F0, dark: 0x124A42)

    // MARK: 文言（端末の言語が日本語なら日本語、それ以外は英語）

    private static var isJapanese: Bool {
        (Locale.preferredLanguages.first ?? "ja").hasPrefix("ja")
    }

    static var title: String { isJapanese ? "使う前に、ひと呼吸" : "A breath before you use it." }

    /// 1行を短くして、折り返しで文が不自然に切れないようにする（改行は、文の区切りに合わせて自分で入れる）。
    static var subtitle: String {
        isJapanese
            ? "今、何に使いたいですか\n『ふと』で少し立ち止まれます\nホーム画面から開いてください"
            : "What do you want to use it for?\nFuto can help you pause.\nOpen it from your Home Screen."
    }

    static var buttonTitle: String { isJapanese ? "ホームに戻る" : "Back to Home" }

    /// ロゴは生成り色なので、ブランドの緑の角丸の台に載せて描く（ライトの生成り地でも、ダークの暗い地でも見える）。
    private static let icon: UIImage? = {
        guard let logo = UIImage(named: "ShieldIcon") else { return nil }
        let side: CGFloat = 112
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            let tile = UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 28)
            UIColor(red: 0x19 / 255, green: 0x64 / 255, blue: 0x59 / 255, alpha: 1).setFill()
            tile.fill()
            let inset: CGFloat = 18
            let target = rect.insetBy(dx: inset, dy: inset)
            let scale = min(target.width / logo.size.width, target.height / logo.size.height)
            let size = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            logo.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            _ = context
        }
    }()

    static func make() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: background,
            icon: icon,
            title: .init(text: title, color: titleColor),
            subtitle: .init(text: subtitle, color: bodyColor),
            primaryButtonLabel: .init(text: buttonTitle, color: buttonText),
            primaryButtonBackgroundColor: buttonBackground,
            secondaryButtonLabel: nil
        )
    }
}
