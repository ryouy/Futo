import SwiftUI

/// チュートリアルで光らせる場所。ホームの要素に `.tutorialTarget(_:)` を付けると、位置が集まる。
enum TutorialTarget: Hashable {
    case status
    case plus
    case main
}

struct TutorialAnchorKey: PreferenceKey {
    static var defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TutorialTarget: Anchor<CGRect>], nextValue: () -> [TutorialTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func tutorialTarget(_ target: TutorialTarget) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

/// ホームの最初の案内。光らせた場所と、押すとどうなるかを、順番に説明する。
struct TutorialOverlay: View {
    let model: AppModel
    let anchors: [TutorialTarget: Anchor<CGRect>]

    private struct Step {
        var target: TutorialTarget?   // nil は光らせない
        var spotlightToolbar = false  // 右上の記録・設定
        var text: String
    }

    /// 今の状態で見えているものだけを案内する。
    private var steps: [Step] {
        var result = [Step(target: .status, text: "ここに、いまの状態が出ます。ふだんは「制限中」です。")]
        if anchors[.plus] != nil {
            result.append(Step(target: .plus, text: "＋で、制限するものを足せます。制限をかけている間は、変えられません。"))
        }
        result.append(Step(target: .main, text: mainText))
        result.append(Step(target: nil, spotlightToolbar: true, text: "右上の時計は記録、歯車は設定です。"))
        result.append(Step(target: nil, text: "準備はできました。"))
        return result
    }

    private var mainText: String {
        if model.mode == .device, model.permission != .approved { return "まず、ここで許可をします。" }
        if model.targetCount == 0 { return "まず、ここで制限するアプリやサイトを選びます。" }
        switch model.restriction {
        case .configured: return "使いたいときは、ここ。ひと呼吸おいてから、使うかを選べます。"
        case .temporarilyUnlocked: return "使い終わったら、ここで制限に戻します。"
        case .off, .unverifiable: return "ここで制限をかけます。ふだんは、かけておくのがおすすめです。"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let all = steps
            let index = min(model.tutorialStep ?? 0, all.count - 1)
            let step = all[index]
            let isLast = index == all.count - 1
            let rect = spotlight(for: step, in: proxy)

            ZStack {
                dim(rect: rect, size: proxy.size)
                bubbleLayer(step: step, index: index, count: all.count, isLast: isLast, rect: rect, size: proxy.size)
            }
            .animation(.easeInOut(duration: 0.4), value: index)
        }
        .ignoresSafeArea()
    }

    // MARK: 光らせる場所

    private func spotlight(for step: Step, in proxy: GeometryProxy) -> CGRect? {
        if step.spotlightToolbar {
            // 右上の記録・設定のボタンのあたり。
            return CGRect(x: proxy.size.width - 118, y: proxy.safeAreaInsets.top, width: 104, height: 44)
        }
        guard let target = step.target, let anchor = anchors[target] else { return nil }
        return proxy[anchor]
    }

    private func dim(rect: CGRect?, size: CGSize) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.6))
            .mask {
                ZStack {
                    Rectangle()
                    if let rect {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .frame(width: rect.width + 16, height: rect.height + 16)
                            .position(x: rect.midX, y: rect.midY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .contentShape(Rectangle())     // 案内の間は、下の画面を押せない
            .onTapGesture {}
    }

    // MARK: 吹き出し

    @ViewBuilder
    private func bubbleLayer(step: Step, index: Int, count: Int, isLast: Bool, rect: CGRect?, size: CGSize) -> some View {
        let card = bubble(step: step, index: index, count: count, isLast: isLast)
            .padding(.horizontal, 24)
        if let rect {
            if rect.midY > size.height * 0.5 {
                // 光らせた場所の上に出す。
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    card
                    Color.clear.frame(height: size.height - rect.minY + 20)
                }
            } else {
                VStack(spacing: 0) {
                    Color.clear.frame(height: rect.maxY + 20)
                    card
                    Spacer(minLength: 0)
                }
            }
        } else {
            card.frame(maxHeight: .infinity)
        }
    }

    private func bubble(step: Step, index: Int, count: Int, isLast: Bool) -> some View {
        VStack(spacing: 14) {
            Text(step.text)
                .font(.body)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(Theme.accent.opacity(i == index ? 1 : 0.25))
                        .frame(width: i == index ? 18 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            HStack {
                if !isLast {
                    Button("スキップ") { model.finishTutorial() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(minHeight: 44)
                }
                Spacer()
                Button(isLast ? "はじめる" : "つぎへ") {
                    if isLast { model.finishTutorial() } else { model.tutorialStep = index + 1 }
                }
                .buttonStyle(FutoCompactButtonStyle())
            }
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .id(index)
        .transition(.opacity)
    }
}
