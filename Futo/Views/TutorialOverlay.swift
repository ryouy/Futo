import SwiftUI

/// チュートリアルで光らせる場所。ホームの要素に `.tutorialTarget(_:)` を付けると、位置が集まる。
enum TutorialTarget: Hashable {
    case status
    case plus
    case main
    /// 右上の記録・設定のボタン
    case header
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
/// 「スキップ」「つぎへ」は、光る場所とは別に、画面の下に固定する。
struct TutorialOverlay: View {
    let model: AppModel
    let anchors: [TutorialTarget: Anchor<CGRect>]

    private struct Step {
        var target: TutorialTarget?   // nil は光らせない
        /// 1行ずつ。句の切れ目で改行し、行の途中で折り返さない長さにする。
        var lines: [String]
    }

    /// 今の状態で見えているものだけを案内する。
    private var steps: [Step] {
        var result = [Step(target: .status, lines: ["ここに、いまの状態が出ます。", "ふだんは「制限中」です。"])]
        if anchors[.plus] != nil {
            result.append(Step(target: .plus, lines: ["＋で、制限するものを足せます。", "制限中は、変えられません。"]))
        }
        result.append(Step(target: .main, lines: mainLines))
        result.append(Step(target: .header, lines: ["右の時計は記録、", "歯車は設定です。"]))
        result.append(Step(target: nil, lines: ["準備はできました。"]))
        return result
    }

    private var mainLines: [String] {
        if model.mode == .device, model.permission != .approved { return ["まず、ここで", "許可をします。"] }
        if model.targetCount == 0 { return ["まず、ここで", "制限するものを選びます。"] }
        switch model.restriction {
        case .configured: return ["使いたいときは、ここ。", "ひと呼吸おいてから、", "使うかを選べます。"]
        case .temporarilyUnlocked: return ["使い終わったら、", "ここで制限に戻します。"]
        case .off, .unverifiable: return ["ここで制限をかけます。", "かけておくのが", "おすすめです。"]
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
                dim(rect: rect)
                if isLast {
                    endView
                } else {
                    bubbleLayer(step: step, rect: rect, size: proxy.size)
                    bottomBar(index: index, bottomInset: proxy.safeAreaInsets.bottom)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: index)
        }
        .ignoresSafeArea()
    }

    // MARK: 光らせる場所

    private func spotlight(for step: Step, in proxy: GeometryProxy) -> CGRect? {
        guard let target = step.target, let anchor = anchors[target] else { return nil }
        return proxy[anchor]
    }

    private func dim(rect: CGRect?) -> some View {
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

    // MARK: 吹き出し（文だけ。ボタンは入れない）

    private func messageCard(_ lines: [String]) -> some View {
        Text(lines.joined(separator: "\n"))
            .font(.body)
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .fixedSize(horizontal: false, vertical: true)   // 行の途中で折り返さない
            .padding(.vertical, 20)
            .padding(.horizontal, 28)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .id(lines)
            .transition(.opacity)
    }

    @ViewBuilder
    private func bubbleLayer(step: Step, rect: CGRect?, size: CGSize) -> some View {
        let card = messageCard(step.lines)
        if let rect {
            if rect.midY > size.height * 0.5 {
                // 光らせた場所の上に出す。
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    card
                    Color.clear.frame(height: size.height - rect.minY + 24)
                }
            } else {
                VStack(spacing: 0) {
                    Color.clear.frame(height: rect.maxY + 24)
                    card
                    Spacer(minLength: 0)
                }
            }
        } else {
            card.frame(maxHeight: .infinity)
        }
    }

    // MARK: 画面下部に固定する操作

    private func bottomBar(index: Int, bottomInset: CGFloat) -> some View {
        VStack {
            Spacer()
            HStack {
                Button("スキップ") { model.finishTutorial() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minHeight: 48)
                Spacer()
                pill("つぎへ") { model.tutorialStep = index + 1 }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, max(bottomInset, 16) + 8)
        }
    }

    /// 最後は、一言のあとに「はじめる」を置く。
    private var endView: some View {
        VStack(spacing: 22) {
            messageCard(["準備はできました。"])
            startButton
        }
        .frame(maxHeight: .infinity)
    }

    /// 「はじめる」：ロゴの丸と同じレモン色で、深い緑の文字。暗い案内画面の上でも、はっきり見える。
    private var startButton: some View {
        Button { model.finishTutorial() } label: {
            HStack(spacing: 8) {
                Text("はじめる")
                Image(systemName: "arrow.right")
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color(red: 25 / 255, green: 100 / 255, blue: 89 / 255))
            .padding(.horizontal, 40)
            .frame(minHeight: 56)
            .background(Capsule().fill(Color(red: 1.0, green: 0.89, blue: 0.54)))
            .shadow(color: Color(red: 1.0, green: 0.89, blue: 0.54).opacity(0.45), radius: 18)
        }
        .buttonStyle(.plain)
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline.weight(.medium))
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 32)
                .frame(minHeight: 50)
                .background(Capsule().fill(Color.white))
        }
        .buttonStyle(.plain)
    }
}
