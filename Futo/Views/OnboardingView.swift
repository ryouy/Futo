import SwiftUI

/// 初回の説明。スプラッシュと同じ深い緑のまま、複数ページをふわっと切り替える。
struct OnboardingView: View {
    let model: AppModel

    private static let background = Color(red: 25 / 255, green: 100 / 255, blue: 89 / 255)
    private static let cream = Color(red: 252 / 255, green: 248 / 255, blue: 240 / 255)

    private struct Page {
        var symbol: String?    // nil はロゴ
        var title: String
        var text: String
    }

    private let pages: [Page] = [
        Page(symbol: nil, title: "使う前に、ひと呼吸。",
             text: "スマホを、ふと開く前に。\n少し立ち止まる時間を作るアプリです。"),
        Page(symbol: "lock.fill", title: "ふだんは、制限をかけておく",
             text: "選んだアプリやサイトは、\nふだんは使えなくします。"),
        Page(symbol: "hourglass", title: "使いたいときは、ひと呼吸",
             text: "使う理由を選んで、少し待ちます。\nそのあと、自分で決めます。"),
        Page(symbol: "moon.stars", title: "そっと、振り返る",
             text: "朝や夜に、短く振り返れます。\n記録は、この端末の中だけにあります。"),
    ]

    @State private var page = 0
    private var isLast: Bool { page == pages.count }   // 最後は「はじめる」の画面

    var body: some View {
        ZStack {
            Self.background.ignoresSafeArea()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { index in
                        pageView(pages[index], index: index).tag(index)
                    }
                    startView.tag(pages.count)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                indicator.padding(.bottom, 20)
                controls
                    .frame(height: 150, alignment: .top)
                    .padding(.horizontal, 28)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.4), value: page)
    }

    // MARK: ページ

    private func pageView(_ content: Page, index: Int) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Group {
                if let symbol = content.symbol {
                    ZStack {
                        Circle().fill(Self.cream.opacity(0.14)).frame(width: 112, height: 112)
                        Image(systemName: symbol)
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(Self.cream)
                    }
                } else {
                    Image("Logo").resizable().scaledToFit().frame(width: 132)
                }
            }
            .accessibilityHidden(true)
            Text(content.title)
                .font(.title2.weight(.medium))
                .foregroundStyle(Self.cream)
                .multilineTextAlignment(.center)
            Text(content.text)
                .foregroundStyle(Self.cream.opacity(0.85))
                .multilineTextAlignment(.center)
                .lineSpacing(6)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
        // 表示中のページだけ、ふわっと現れる。
        .opacity(page == index ? 1 : 0)
    }

    private var startView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image("Logo").resizable().scaledToFit().frame(width: 96).accessibilityHidden(true)
            Text("はじめましょう")
                .font(.title2.weight(.medium))
                .foregroundStyle(Self.cream)
            Text("どちらで始めますか？")
                .foregroundStyle(Self.cream.opacity(0.85))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .opacity(isLast ? 1 : 0)
    }

    // MARK: インジケータと操作

    private var indicator: some View {
        HStack(spacing: 8) {
            ForEach(0...pages.count, id: \.self) { index in
                Capsule()
                    .fill(Self.cream.opacity(index == page ? 1 : 0.3))
                    .frame(width: index == page ? 22 : 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(page + 1)ページ目、全\(pages.count + 1)ページ")
    }

    @ViewBuilder
    private var controls: some View {
        if isLast {
            VStack(spacing: 12) {
                pill("実機で設定する", filled: true) { model.completeOnboarding(mode: .device) }
                pill("デモで試す", filled: false) { model.completeOnboarding(mode: .demo) }
                Text("デモでは、実際のアプリは制限されません。")
                    .font(.footnote)
                    .foregroundStyle(Self.cream.opacity(0.7))
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 4) {
                pill("つぎへ", filled: true) { page += 1 }
                Button("スキップ") { page = pages.count }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Self.cream.opacity(0.75))
                    .frame(minHeight: 44)
            }
            .transition(.opacity)
        }
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 54)
                .foregroundStyle(filled ? Self.background : Self.cream)
                .background(Capsule().fill(filled ? Self.cream : Color.clear))
                .overlay(Capsule().stroke(Self.cream.opacity(filled ? 0 : 0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }
}
