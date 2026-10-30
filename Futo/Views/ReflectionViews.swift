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
                Text(card.kind.title).font(.title3.weight(.medium))
                VStack(spacing: 10) {
                    ForEach(Array(card.lines.enumerated()), id: \.offset) { _, line in
                        Text(line).oneLine(0.75)
                    }
                }
                .multilineTextAlignment(.center)
                Button(tr("わかった"), action: onClose)
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
/// 選んだ答えを、少しの間だけ選択状態で見せてから閉じる（突然切り替わらないように）。連打しても、記録は1回だけ。
struct ReflectionQuestionOverlay: View {
    let onAnswer: (Reflection) -> Void
    @State private var chosen: Reflection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 選んでから閉じるまでの間（約0.3秒）。
    static let confirmDelay: Duration = .milliseconds(300)

    private func choose(_ reflection: Reflection) {
        guard chosen == nil else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.2)) { chosen = reflection }
        Task { @MainActor in
            try? await Task.sleep(for: Self.confirmDelay)
            onAnswer(reflection)
        }
    }

    var body: some View {
        ZStack {
            SoftBackdrop()
            VStack(spacing: 14) {
                Image(systemName: "leaf")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(tr("さっきの時間は、どうでしたか？"))
                    .font(.title3.weight(.medium))
                    .oneLine(0.8)
                    .padding(.bottom, 6)
                ForEach([Reflection.satisfied, .neutral, .wishedLess], id: \.self) { reflection in
                    Button(reflection.label) { choose(reflection) }
                        .buttonStyle(FutoButtonStyle(prominent: false))
                        .opacity(chosen == nil || chosen == reflection ? 1 : 0.3)
                        .scaleEffect(chosen == reflection && !reduceMotion ? 0.97 : 1)
                        .accessibilityAddTraits(chosen == reflection ? .isSelected : [])
                }
                Button(tr("答えない")) { choose(.skipped) }
                    .buttonStyle(FutoTextButtonStyle())
                    .opacity(chosen == nil || chosen == .skipped ? 1 : 0.3)
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
            Button(tr("変更する")) { confirming = true }
                .buttonStyle(FutoButtonStyle())
            Button(tr("今のまま")) { model.resolveSuggestion(.kept) }
                .buttonStyle(FutoButtonStyle(prominent: false))
            Button(tr("今回は見送る")) { model.resolveSuggestion(.skipped) }
                .buttonStyle(FutoTextButtonStyle())
        }
        .card(tint: Theme.softBlue)
        .confirmationDialog(
            tr("{0} から {1} に変更しますか？", "\(suggestion.currentText)", "\(suggestion.proposedText)"),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(tr("変更する")) { model.applySuggestion() }
            Button(tr("キャンセル"), role: .cancel) {}
        }
    }
}
