import SwiftUI

/// 朝・夜の振り返りカード。閉じられ、未回答の催促はしない。
struct ReflectionCardView: View {
    let card: ReflectionCard
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: card.kind == .morning ? "sunrise" : "moon.stars")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(card.title).font(.headline.weight(.medium))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("閉じる")
            }
            ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                Text(line).lineSpacing(4)
            }
        }
        .card(tint: Theme.softBlue)
    }
}

/// 設定改善の提案。「変更する」は、現在値と変更後の値を見せて、確認のあとに適用する。
struct SuggestionCardView: View {
    let model: AppModel
    let suggestion: Suggestion
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.title).font(.headline.weight(.medium))
            Text(suggestion.evidence)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
            Button("変更する") { confirming = true }
                .buttonStyle(FutoButtonStyle())
            Button("今のまま") { model.resolveSuggestion(.kept) }
                .buttonStyle(FutoButtonStyle(prominent: false))
            Button("今回は見送る") { model.resolveSuggestion(.skipped) }
                .buttonStyle(FutoTextButtonStyle())
        }
        .card(tint: Theme.softBlue)
        .confirmationDialog(
            "\(suggestion.currentText) から \(suggestion.proposedText) に変更しますか？",
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button("変更する") { model.applySuggestion() }
            Button("キャンセル", role: .cancel) {}
        }
    }
}
