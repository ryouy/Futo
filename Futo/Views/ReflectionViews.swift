import SwiftUI

/// 画面全体をやわらかく覆う地。後ろの画面は、うっすら透ける。
private struct SoftBackdrop: View {
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(Theme.background.opacity(0.88))
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {}
    }
}

/// 朝・夜の振り返り。アプリを開いたとき、画面全体をやわらかく覆うカードで出し、「わかった」で閉じる。
struct ReflectionOverlay: View {
    let card: ReflectionCard
    let onClose: () -> Void

    var body: some View {
        ZStack {
            SoftBackdrop()
            VStack(spacing: 20) {
                Image(systemName: card.kind == .morning ? "sunrise" : "moon.stars")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(card.title).font(.title3.weight(.medium))
                VStack(spacing: 10) {
                    ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).oneLine(0.75)
                    }
                }
                .multilineTextAlignment(.center)
                Button("わかった", action: onClose)
                    .buttonStyle(FutoButtonStyle())
                    .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(Theme.softBlue, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(.horizontal, 24)
        }
    }
}

/// 「さっきの時間は、どうでしたか？」。一時解除のあと、戻ってきたときに、画面全体を覆うカードで尋ねる。
struct ReflectionQuestionOverlay: View {
    let onAnswer: (Reflection) -> Void

    var body: some View {
        ZStack {
            SoftBackdrop()
            VStack(spacing: 14) {
                Image(systemName: "leaf")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("さっきの時間は、どうでしたか？")
                    .font(.title3.weight(.medium))
                    .oneLine(0.8)
                    .padding(.bottom, 6)
                ForEach([Reflection.satisfied, .neutral, .wishedLess], id: \.self) { reflection in
                    Button(reflection.label) { onAnswer(reflection) }
                        .buttonStyle(FutoButtonStyle(prominent: false))
                }
                Button("答えない") { onAnswer(.skipped) }
                    .buttonStyle(FutoTextButtonStyle())
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(Theme.softBlue, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
            .padding(.horizontal, 24)
        }
    }
}

/// 設定改善の提案。「変更する」は、現在値と変更後の値を見せて、確認のあとに適用する。
struct SuggestionCardView: View {
    let model: AppModel
    let suggestion: Suggestion
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.title).font(.headline.weight(.medium)).oneLine(0.8)
            Text(suggestion.evidence)
                .oneLine(0.8)
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
