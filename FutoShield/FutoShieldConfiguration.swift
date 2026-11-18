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

    // MARK: 色（本体がテーマから決めた色。App Groupから読む。読めなければ、深緑）

    private static var theme: ShieldTheme { ShieldTheme.load() }

    // MARK: 文言（端末の言語が日本語なら日本語、それ以外は英語）

    private static var isJapanese: Bool {
        (Locale.preferredLanguages.first ?? "ja").hasPrefix("ja")
    }

    static var title: String { isJapanese ? "使う前に、ひと呼吸" : "A breath before you use it" }

    /// 1行を短くして、折り返しで文が不自然に切れないようにする（改行は、文の区切りに合わせて自分で入れる）。
    static var subtitle: String {
        isJapanese
            ? "今、何に使いたいですか\n『ふと』で少し立ち止まれます\nホーム画面から開いてください"
            : "What do you want to use it for?\nFuto can help you pause\nOpen it from your Home Screen"
    }

    static var buttonTitle: String { isJapanese ? "ホームに戻る" : "Back to Home" }

    /// ロゴは生成り色なので、テーマ色の角丸の台に載せて描く（ライトの生成り地でも、ダークの暗い地でも見える）。
    private static func icon(tile: UInt32) -> UIImage? {
        guard let logo = UIImage(named: "ShieldIcon") else { return nil }
        let side: CGFloat = 112
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { _ in
            let rect = CGRect(x: 0, y: 0, width: side, height: side)
            ShieldTheme.color(tile).setFill()
            UIBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: 28).fill()
            let target = rect.insetBy(dx: 18, dy: 18)
            let scale = min(target.width / logo.size.width, target.height / logo.size.height)
            let size = CGSize(width: logo.size.width * scale, height: logo.size.height * scale)
            logo.draw(in: CGRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
        }
    }

    static func make() -> ShieldConfiguration {
        let theme = theme
        return ShieldConfiguration(
            backgroundBlurStyle: nil,
            backgroundColor: ShieldTheme.uiColor(theme.background),
            icon: icon(tile: theme.tile),
            title: .init(text: title, color: ShieldTheme.uiColor(theme.title)),
            subtitle: .init(text: subtitle, color: ShieldTheme.uiColor(theme.body)),
            primaryButtonLabel: .init(text: buttonTitle, color: ShieldTheme.uiColor(theme.buttonText)),
            primaryButtonBackgroundColor: ShieldTheme.uiColor(theme.buttonBackground),
            secondaryButtonLabel: nil
        )
    }
}
