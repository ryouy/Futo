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
    /// 指で動かしている間のずれ
    @State private var drag: CGFloat = 0
    /// スプラッシュが消えるのに合わせて、ゆっくり現れる（見直しのときは、すぐ）。
    @State private var appeared = false
    private var isLast: Bool { page == pages.count }   // 最後は「はじめる」の画面

    var body: some View {
        ZStack {
            Self.background.ignoresSafeArea()
            VStack(spacing: 0) {
                pager

                indicator.padding(.bottom, 20)
                    .animation(.easeInOut(duration: 0.4), value: page)
                controls
                    .frame(height: 150, alignment: .top)
                    .padding(.horizontal, 28)
                    .animation(.easeInOut(duration: 0.4), value: isLast)
            }
            // 背景はスプラッシュと同じ緑のまま、中身だけがゆっくり現れる。
            .opacity(appeared ? 1 : 0)
            .animation(.easeInOut(duration: 0.9), value: appeared)
        }
        .preferredColorScheme(.dark)
        .task {
            if !model.isOnboardingReplay { try? await Task.sleep(for: .milliseconds(900)) }
            appeared = true
        }
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
    }

    private var startView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            Image("Logo").resizable().scaledToFit().frame(width: 96).accessibilityHidden(true)
            Text("はじめましょう")
                .font(.title2.weight(.medium))
                .foregroundStyle(Self.cream)
            Text(model.isOnboardingReplay ? "説明は以上です。" : "どちらで始めますか？")
                .foregroundStyle(Self.cream.opacity(0.85))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: ページの横スライド

    private var pageCount: Int { pages.count + 1 }   // 説明のページ＋最後の「はじめましょう」
    private let slide = Animation.easeInOut(duration: 0.65)

    /// ページを横に並べて動かす。ボタンでもスワイプでも、前のページが左へゆるっと流れる。
    private var pager: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Group {
                        if index < pages.count { pageView(pages[index], index: index) } else { startView }
                    }
                    .frame(width: width)
                    .accessibilityHidden(index != page)
                }
            }
            .offset(x: -CGFloat(page) * width + drag)
            .animation(slide, value: page)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        // 端では、抵抗をつけて少ししか動かさない。
                        let atStart = page == 0 && value.translation.width > 0
                        let atEnd = page == pageCount - 1 && value.translation.width < 0
                        drag = (atStart || atEnd) ? value.translation.width / 4 : value.translation.width
                    }
                    .onEnded { value in
                        let threshold = width * 0.2
                        var next = page
                        if value.translation.width < -threshold || value.predictedEndTranslation.width < -width * 0.5 {
                            next = min(page + 1, pageCount - 1)
                        } else if value.translation.width > threshold || value.predictedEndTranslation.width > width * 0.5 {
                            next = max(page - 1, 0)
                        }
                        withAnimation(slide) {
                            drag = 0
                            page = next
                        }
                    }
            )
        }
        .clipped()
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
                if model.isOnboardingReplay {
                    // 開発用の見直し：モードも制限も変えず、閉じるだけ。
                    pill("閉じる", filled: true) { model.finishOnboardingReplay() }
                } else {
                    pill("実機で設定する", filled: true) { model.completeOnboarding(mode: .device) }
                    pill("デモで試す", filled: false) { model.completeOnboarding(mode: .demo) }
                    Text("デモでは、実際のアプリは制限されません。")
                        .font(.footnote)
                        .foregroundStyle(Self.cream.opacity(0.7))
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 4) {
                pill("つぎへ", filled: true) { withAnimation(slide) { page += 1 } }
                Button("スキップ") { withAnimation(slide) { page = pages.count } }
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
