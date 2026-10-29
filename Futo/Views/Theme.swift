import SwiftUI
import UIKit

/// 選べるテーマカラー。背景の温かい生成り色は共通で、アクセント色と淡い面の色だけが変わる。
enum ThemeColor: String, CaseIterable, Identifiable {
    case wakaba
    case sora
    case sakura
    case fuji

    var id: String { rawValue }

    var name: String {
        switch self {
        case .wakaba: return "深緑"
        case .sora: return "空"
        case .sakura: return "桜"
        case .fuji: return "藤"
        }
    }

    /// (ライト, ダーク)。ライトは生成り色の地に濃いめの差し色。
    /// ダークは、黒に寄せず、やわらかい深緑グレーの地に、少し持ち上げたカードと、パステル調の差し色にして、
    /// 夜でも張りつめない雰囲気にする。
    struct Palette {
        var accent: (UInt32, UInt32)
        var backgroundTop: (UInt32, UInt32)
        var backgroundBottom: (UInt32, UInt32)
        var card: (UInt32, UInt32)
        var soft: (UInt32, UInt32)
    }

    var palette: Palette {
        switch self {
        case .wakaba:
            return Palette(accent: (0x196459, 0x8FD0BD), backgroundTop: (0xFCF8F0, 0x26312E),
                           backgroundBottom: (0xE8F1EE, 0x1F2926), card: (0xFFFEFA, 0x2F3B37), soft: (0xDDEBE7, 0x2B3D39))
        case .sora:
            return Palette(accent: (0x46789A, 0x9CC9E6), backgroundTop: (0xFCF8F0, 0x262D34),
                           backgroundBottom: (0xEAF1F5, 0x1F262D), card: (0xFFFEFA, 0x2F3841), soft: (0xE1EDF4, 0x2B3945))
        case .sakura:
            return Palette(accent: (0xA25A72, 0xEAB0C2), backgroundTop: (0xFCF8F0, 0x312B2D),
                           backgroundBottom: (0xF7ECEE, 0x282224), card: (0xFFFEFA, 0x3A3235), soft: (0xF5E3E8, 0x3B3034))
        case .fuji:
            return Palette(accent: (0x6F5CA3, 0xC4B3EE), backgroundTop: (0xFCF8F0, 0x2C2B34),
                           backgroundBottom: (0xF0ECF6, 0x24232C), card: (0xFFFEFA, 0x35343F), soft: (0xE8E3F3, 0x363448))
        }
    }
}

/// 現在のテーマ。Observationにより、`Theme` の色を読んでいる画面は、変更時に自動で再描画される。
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    private static let key = "settings.themeColor"

    private(set) var color: ThemeColor

    private init() {
        color = ThemeColor(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .wakaba
    }

    func select(_ newColor: ThemeColor) {
        color = newColor
        UserDefaults.standard.set(newColor.rawValue, forKey: Self.key)
    }
}

/// 温かい生成り色と、選んだテーマの落ち着いた色。強い白・黒や原色を避け、ダークモードでも同じ穏やかさを保つ。
enum Theme {
    private static func dynamic(_ pair: (UInt32, UInt32)) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(pair.1) : rgb(pair.0) })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    private static var palette: ThemeColor.Palette { ThemeStore.shared.color.palette }

    static var backgroundTop: Color { dynamic(palette.backgroundTop) }
    static var backgroundBottom: Color { dynamic(palette.backgroundBottom) }
    static var card: Color { dynamic(palette.card) }
    static var accent: Color { dynamic(palette.accent) }
    /// アクセント色の上に置く文字色
    static var onAccent: Color { dynamic(((0xFFFEFA), 0x151816)) }
    /// 補足や案内に使う、テーマ色の淡い面。
    static var softBlue: Color { dynamic(palette.soft) }
    /// ほんのり暖かい色。お知らせ用。赤い警告色は使わない。
    static var softPeach: Color { dynamic((0xF8EADF, 0x443A31)) }

    /// 文字の色。ダークでは、真っ白ではなく、やわらかい生成り色。ライトはOS標準のまま。
    static var text: Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? rgb(0xEEE9DF) : .label })
    }

    /// 円グラフの色。テーマ色を軸に、見分けやすい控えめな色を並べる。
    static var chartColors: [Color] {
        [accent, accent.opacity(0.5), dynamic((0xE2B48C, 0xD9B48F)), dynamic((0xB9B6AE, 0x8F938E)), dynamic((0xA9C4D4, 0x84A9BC))]
    }

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

struct CardStyle: ViewModifier {
    var tint: Color

    func body(content: Content) -> some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Theme.accent.opacity(0.10), lineWidth: 1)
            )
    }
}

extension View {
    func card(tint: Color? = nil) -> some View { modifier(CardStyle(tint: tint ?? Theme.card)) }
}

/// 主操作・副操作とも、押しやすくやわらかい形のボタン。
struct FutoButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 16)
            .foregroundStyle(prominent ? Theme.onAccent : Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(prominent ? Theme.accent : Theme.accent.opacity(0.14))
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

extension AnyTransition {
    /// 古い画面が先に消え、そのあとに新しい画面が現れる。2つが重なって文字が二重に見えるのを避ける。
    static var sequentialFade: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.2)),
            removal: .opacity.animation(.easeIn(duration: 0.2)))
    }
}

/// 内容を画面の縦方向の中央に置く。長くなる（文字拡大など）ときはスクロールできる。
struct CenteredScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .center)
            }
        }
    }
}

/// 単一・複数選択の1行。目的選択とアプリ選択で共通に使う。
struct ChoiceRow<Content: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        Button(action: action) {
            HStack {
                content
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Theme.accent)
            }
            .frame(minHeight: 58)
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(isOn ? Theme.accent : Theme.accent.opacity(0.10), lineWidth: isOn ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 開発用など、小さく控えめなボタン。
struct FutoCompactButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(Capsule().fill(Theme.accent.opacity(0.12)))
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// 目立たせたくない操作用の、文字だけのボタン。
struct FutoTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// デモ中は全画面の上部に常時表示する。
struct DemoBanner: View {
    var body: some View {
        Label("デモモード：実際のアプリは制限しません", systemImage: "info.circle")
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(Theme.softBlue)
            .accessibilityElement(children: .combine)
    }
}

extension View {
    func demoBanner(_ mode: AppMode) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            if mode == .demo { DemoBanner() }
        }
    }
}

/// ホームや説明で使う、控えめな葉のしるし。
struct LeafMark: View {
    var size: CGFloat = 22
    var body: some View {
        Image(systemName: "leaf")
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(Theme.accent)
            .accessibilityHidden(true)
    }
}

extension View {
    /// 1行に収める。入りきらないときは少しだけ縮める（折り返さない）。
    func oneLine(_ minimumScale: CGFloat = 0.7) -> some View {
        lineLimit(1).minimumScaleFactor(minimumScale)
    }
}

/// 設定のまとまり。行の背景を、アプリのカードの色にそろえる（ダークで標準の灰色が浮かないように）。
struct CardSection<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Section { content }
            .listRowBackground(Theme.card)
    }
}
