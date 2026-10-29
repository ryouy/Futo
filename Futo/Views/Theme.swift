import SwiftUI
import UIKit

/// 温かい白と落ち着いた緑。ダークモードでは暗い暖色の背景に明るい緑。
enum Theme {
    static let background = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.11, green: 0.11, blue: 0.10, alpha: 1)
        : UIColor(red: 0.985, green: 0.973, blue: 0.949, alpha: 1) })
    static let card = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.16, green: 0.16, blue: 0.15, alpha: 1)
        : UIColor.white })
    static let accent = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.49, green: 0.75, blue: 0.60, alpha: 1)
        : UIColor(red: 0.20, green: 0.45, blue: 0.32, alpha: 1) })
    static let softBlue = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.20, green: 0.27, blue: 0.33, alpha: 1)
        : UIColor(red: 0.90, green: 0.94, blue: 0.97, alpha: 1) })
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

/// 主操作・副操作とも十分なタップ領域を持つボタン。
struct FutoButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 12)
            .foregroundStyle(prominent ? Color(uiColor: .systemBackground) : Theme.accent)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(prominent ? Theme.accent : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Theme.accent, lineWidth: prominent ? 0 : 1.5)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
    }
}

/// デモ中は全画面の上部に常時表示する。
struct DemoBanner: View {
    var body: some View {
        Label("デモモード：実際のアプリは制限しません", systemImage: "info.circle")
            .font(.footnote.weight(.semibold))
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
