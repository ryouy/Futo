import SwiftUI
import UIKit

/// 温かい生成り色と、くすんだ若葉色。強い白・黒や原色を避け、ダークモードでも同じ穏やかさを保つ。
enum Theme {
    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func rgb(_ hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    static let backgroundTop = dynamic(light: rgb(0xFCF8F0), dark: rgb(0x1E1D1A))
    static let backgroundBottom = dynamic(light: rgb(0xEFF3E8), dark: rgb(0x1A1F1B))
    static let card = dynamic(light: rgb(0xFFFEFA), dark: rgb(0x282722))
    static let accent = dynamic(light: rgb(0x4F7F63), dark: rgb(0x93C7A7))
    /// アクセント色の上に置く文字色
    static let onAccent = dynamic(light: rgb(0xFFFEFA), dark: rgb(0x14231A))
    /// 落ち着いた薄い青。補足や案内に必要な箇所だけで使う。
    static let softBlue = dynamic(light: rgb(0xE5EEF1), dark: rgb(0x26343A))
    /// ほんのり暖かい色。お知らせ用。赤い警告色は使わない。
    static let softPeach = dynamic(light: rgb(0xF8EADF), dark: rgb(0x3A3029))

    static let background = LinearGradient(
        colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
}

struct CardStyle: ViewModifier {
    var tint: Color = Theme.card

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
    func card(tint: Color = Theme.card) -> some View { modifier(CardStyle(tint: tint)) }
}

/// 主操作・副操作とも、押しやすくやわらかい形のボタン。
struct FutoButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.medium))
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
                content.foregroundStyle(.primary)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(Theme.accent)
            }
            .frame(minHeight: 58)
            .padding(.horizontal, 20)
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
