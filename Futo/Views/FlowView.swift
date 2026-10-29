import SwiftUI

/// 目的選択 → 待機 → 最終選択 → 結果。ホームから全画面で表示する。
struct FlowView: View {
    let model: AppModel

    /// 表示中の段階。画面を閉じている最中に中身が変わって見えないよう、閉じる間は最後の段階を保つ。
    private struct Stage {
        var id: String
        var session: Session?
        var outcome: SessionOutcome?
    }

    @State private var shown: Stage?

    init(model: AppModel) {
        self.model = model
        _shown = State(initialValue: Self.currentStage(of: model))
    }

    private static func currentStage(of model: AppModel) -> Stage? {
        if let result = model.lastResult {
            return Stage(id: "result-\(model.awaitingUnlockSelection)", session: nil, outcome: result)
        }
        guard let session = model.activeSession else { return nil }
        switch session.phase {
        case .choosingPurpose: return Stage(id: "purpose", session: session)
        case .waiting: return Stage(id: "wait", session: session)
        case .awaitingChoice: return Stage(id: "choice", session: session)
        case .completed, .interrupted: return nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if let shown {
                    content(shown)
                        .id(shown.id)
                        .transition(.sequentialFade)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: shown?.id)
            .background(Theme.background.ignoresSafeArea())
        }
        .demoBanner(model.mode)
        .onChange(of: Self.currentStage(of: model)?.id) { _, _ in
            // 閉じている間（showFlow が false）は更新しない。
            if model.showFlow, let next = Self.currentStage(of: model) { shown = next }
        }
        .onAppear { if shown == nil { model.closeFlow() } }
    }

    @ViewBuilder
    private func content(_ stage: Stage) -> some View {
        switch stage.id {
        case "purpose": PurposeView(model: model)
        case "wait":
            if let session = stage.session { WaitView(model: model, session: session) }
        case "choice": FinalChoiceView(model: model)
        default:
            if let outcome = stage.outcome { ResultView(model: model, outcome: outcome) }
        }
    }
}

private struct FlowTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.title2.weight(.medium))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

struct PurposeView: View {
    let model: AppModel
    @State private var selected: Purpose?

    var body: some View {
        CenteredScroll {
            VStack(spacing: 14) {
                FlowTitle(text: "今、どんなことに使いたいですか？")
                Text("このあと、\(model.waitDurationText)だけ立ち止まります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                ForEach(Purpose.allCases) { item in
                    ChoiceRow(isOn: selected == item) { selected = item } content: {
                        Text(item.label)
                    }
                }
                Button("ひと呼吸おく") { model.choosePurpose(selected) }
                    .buttonStyle(FutoButtonStyle())
                    .disabled(selected == nil)
                    .padding(.top, 10)
                Button("答えずに進む") { model.choosePurpose(nil) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.leavePurposeStep() } label: {
                    Label("戻る", systemImage: "chevron.backward")
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
struct WaitView: View {
    let model: AppModel
    @State private var controller: WaitController
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    /// 最初に言葉だけを見せ、少し置いてからタイマーを現す。
    @State private var showTimer = false

    init(model: AppModel, session: Session) {
        self.model = model
        _controller = State(initialValue: WaitController(session: session, store: model.sessions))
    }

    private func timeText(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        CenteredScroll {
            VStack(spacing: 24) {
                FlowTitle(text: "少し、立ち止まってみましょう。")
                Text("\(model.waitDurationText)、ゆっくり息をしてみましょう。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                timer
                    .opacity(showTimer ? 1 : 0)
                    .padding(.vertical, 12)

                Button("やめてホームへ") { model.endBreath() }
                    .buttonStyle(FutoTextButtonStyle())
                    .opacity(showTimer ? 1 : 0)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        // scenePhaseが変わるたびにタスクが作り直されるため、タイマーは常に1つだけ。
        .task(id: scenePhase) {
            guard scenePhase == .active else {
                controller.deactivate()
                return
            }
            controller.activate()
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                controller.tick()
            }
            controller.deactivate()
        }
        .task {
            // 言葉を読む間を置いてから、タイマーを静かに現す。
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeInOut(duration: 0.5)) { showTimer = true }
        }
        .onAppear {
            // ゆっくりした呼吸のような、ごく控えめな動き。視差・動きを減らす設定のときは動かさない。
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathing = true }
        }
        .onDisappear { controller.deactivate() }
    }

    /// 進捗と残り時間は、毎フレーム時計から求める（250msごとの更新ではカクつくため）。
    private var timer: some View {
        TimelineView(.animation(paused: scenePhase != .active)) { _ in
            let remaining = controller.liveRemaining()
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(breathing ? 0.16 : 0.08))
                    .padding(18)
                Circle().stroke(Theme.softBlue, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: controller.liveProgress())
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(timeText(remaining))
                    .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                    .accessibilityLabel("残り \(Int(remaining.rounded(.up))) 秒")
            }
        }
        .frame(width: 200, height: 200)
    }
}

struct FinalChoiceView: View {
    let model: AppModel

    private var footnote: String {
        if model.canTemporarilyUnlock {
            return "「使いたい」を選ぶと、選んだものをしばらく使えます。"
        }
        if model.mode == .demo {
            return "デモでは、実際のアプリの制限は変わりません。"
        }
        return "この設定では、どちらを選んでも制限は解除されません。"
    }

    var body: some View {
        CenteredScroll {
            VStack(spacing: 16) {
                FlowTitle(text: "今も使いたいですか？")
                    .padding(.bottom, 12)
                Button("やめておく") { model.finish(.deferred) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                Button("使いたい") { model.finish(.wantsToUse) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ResultView: View {
    let model: AppModel
    let outcome: SessionOutcome

    private var wantsToUseMessage: String {
        switch model.unlockResult {
        case .started(let until):
            return "選んだものを使えます。約\(SharedState.unlockUsageMinutes)分使うか、\(until.formatted(date: .omitted, time: .shortened))になると、制限に戻ります。"
        case .failed:
            return "一時解除を始められなかったため、制限は続いています。"
        case .unsupported:
            return "この設定では、一時解除は使えません。使うには、設定で「いつも制限する」をオフにしてください。"
        case nil:
            return model.mode == .demo
                ? "デモでは、実際の制限は変わりません。"
                : "制限は続いています。"
        }
    }

    var body: some View {
        if model.awaitingUnlockSelection {
            UnlockChooserView(model: model)
        } else {
            CenteredScroll {
                VStack(spacing: 16) {
                    FlowTitle(text: "記録しました。")
                    if outcome == .wantsToUse {
                        Text(wantsToUseMessage)
                            .multilineTextAlignment(.center)
                            .lineSpacing(5)
                    }
                    Button("ホームへ") { model.closeFlow() }
                        .buttonStyle(FutoButtonStyle())
                        .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
