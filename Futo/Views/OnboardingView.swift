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

    private var pages: [Page] {
        [
        Page(symbol: nil, title: tr("使う前に、ひと呼吸。"),
             text: tr("スマホを開く前に、\n少し立ち止まる時間をつくるアプリです。")),
        Page(symbol: "lock.fill", title: tr("ふだんは、制限をかけておく"),
             text: tr("選んだアプリやサイトは、\nふだんは使えなくします。")),
        Page(symbol: "hourglass", title: tr("使いたいときは、ひと呼吸"),
             text: tr("使う理由を選んで、少し待ちます。\nそのあと、自分で決めます。")),
        Page(symbol: "moon.stars", title: tr("そっと、振り返る"),
             text: tr("朝や夜に、短く振り返れます。\n記録は、選ばない限り、\nこの端末の中だけに保存されます。")),
        ]
    }

    @Namespace private var languageNamespace
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// ページ移動中は、次の操作を受け付けない（連続操作でアニメーションが重ならないように）。
    @State private var isSliding = false
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
        .overlay(alignment: .topTrailing) {
            languageSwitch
                .padding(.top, 10)
                .padding(.trailing, 20)
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
            Text(tr("はじめましょう"))
                .font(.title2.weight(.medium))
                .foregroundStyle(Self.cream)
            Text(model.isOnboardingReplay ? tr("説明は以上です。") : tr("準備はできました。"))
                .foregroundStyle(Self.cream.opacity(0.85))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 言語の切り替え

    /// 「日本語 | English」。選んでいるほうの下に、白いカプセルがすべるように動く。
    private var languageSwitch: some View {
        HStack(spacing: 0) {
            ForEach(AppLanguage.allCases) { language in
                let selected = LanguageStore.shared.language == language
                Button {
                    withAnimation(.easeInOut(duration: 0.35)) { LanguageStore.shared.select(language) }
                } label: {
                    Text(language.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(selected ? Self.background : Self.cream.opacity(0.85))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(Self.cream)
                                    .matchedGeometryEffect(id: "language", in: languageNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Self.cream.opacity(0.16)))
        .overlay(Capsule().stroke(Self.cream.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("言語 / Language")
    }

    // MARK: ページの横スライド

    private var pageCount: Int { pages.count + 1 }   // 説明のページ＋最後の「はじめましょう」
    /// ページの横移動。急に加速・停止しない、なだらかなease-in-out（約0.45秒）。
    private var slide: Animation { .timingCurve(0.4, 0.0, 0.2, 1.0, duration: slideDuration) }

    /// ページ移動の長さ（視差効果を減らす設定では、移動せずに溶けるように切り替える）。
    private var slideDuration: Double { reduceMotion ? 0.3 : 0.45 }

    /// ページを移る。移動中の操作は無視する。
    private func go(to target: Int) {
        let clamped = min(max(target, 0), pageCount - 1)
        guard clamped != page, !isSliding else { return }
        isSliding = true
        withAnimation(slide) { page = clamped }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(slideDuration))
            isSliding = false
        }
    }

    /// ページを横に並べて動かす。ボタンでもスワイプでも、前のページが左へゆるっと流れる。
    /// 「視差効果を減らす」設定では、横に動かさず、ページを重ねて、ふわっと切り替える。
    private var pager: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Group {
                if reduceMotion {
                    ZStack {
                        ForEach(0..<pageCount, id: \.self) { index in
                            pageContent(index)
                                .frame(width: width)
                                .opacity(index == page ? 1 : 0)
                                .accessibilityHidden(index != page)
                        }
                    }
                    .animation(slide, value: page)
                } else {
                    HStack(spacing: 0) {
                        ForEach(0..<pageCount, id: \.self) { index in
                            pageContent(index)
                                .frame(width: width)
                                .accessibilityHidden(index != page)
                        }
                    }
                    .offset(x: -CGFloat(page) * width + drag)
                    .animation(slide, value: page)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard !reduceMotion, !isSliding else { return }
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
                        if isSliding {
                            withAnimation(slide) { drag = 0 }
                        } else if next != page {
                            isSliding = true
                            withAnimation(slide) { drag = 0; page = next }
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(slideDuration))
                                isSliding = false
                            }
                        } else {
                            withAnimation(slide) { drag = 0 }
                        }
                    }
            )
        }
        .clipped()
    }

    @ViewBuilder
    private func pageContent(_ index: Int) -> some View {
        if index < pages.count { pageView(pages[index], index: index) } else { startView }
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
        .accessibilityLabel(tr("{0}ページ目、全{1}ページ", "\(page + 1)", "\(pages.count + 1)"))
    }

    @ViewBuilder
    private var controls: some View {
        if isLast {
            VStack(spacing: 12) {
                if model.isOnboardingReplay {
                    // 開発用の見直し：モードも制限も変えず、閉じるだけ。
                    pill(tr("閉じる"), filled: true) { model.finishOnboardingReplay() }
                } else {
                    pill(tr("はじめる"), filled: true) { model.completeOnboarding(mode: .device) }
                }
            }
            .transition(.opacity)
        } else {
            VStack(spacing: 4) {
                pill(tr("つぎへ"), filled: true) { go(to: page + 1) }
                Button(tr("スキップ")) { go(to: pages.count) }
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
