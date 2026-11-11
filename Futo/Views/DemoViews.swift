import SwiftUI

/// デモ中であることを、画面の上に、はっきり出す帯。デモの間は、共有・フレンドの画面すべてに付ける。
struct DemoBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "theatermasks.fill").foregroundStyle(Theme.accentText).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("デモ中")).font(.footnote.weight(.bold)).foregroundStyle(Theme.accentText)
                Text(tr("架空のデータです。実際の相手には、何も届きません")).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.softBlue.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, 20).padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct DemoBannerModifier: ViewModifier {
    @Environment(SharingModel.self) private var sharing

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .top, spacing: 0) {
            if sharing.isDemo { DemoBanner() }
        }
    }
}

extension View {
    /// デモ中だけ、上に「デモ中」の帯を出す。
    func demoBanner() -> some View { modifier(DemoBannerModifier()) }
}

/// ログイン画面の「デモを試す」。ログインなしで、架空のデータで、共有とフレンドの操作を試せる。
struct DemoEntry: View {
    @Environment(SharingModel.self) private var sharing

    var body: some View {
        if sharing.canTryDemo {
            Button { Task { await sharing.enterDemo() } } label: {
                Label(tr("デモを試す"), systemImage: "theatermasks")
            }
            .buttonStyle(FutoButtonStyle(prominent: false))
            .disabled(sharing.isWorking)
            Text(tr("ログインなしで、架空のデータで、共有とフレンドの操作を試せます\n実際の相手には、何も届きません"))
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
