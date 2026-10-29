import SwiftUI

/// 目的選択 → 待機 → 最終選択 → 結果。ホームから全画面で表示する。
struct FlowView: View {
    let model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if let result = model.lastResult {
                    ResultView(model: model, outcome: result)
                } else if let session = model.activeSession {
                    switch session.phase {
                    case .choosingPurpose:
                        PurposeView(model: model)
                    case .waiting:
                        WaitView(model: model, session: session)
                    case .awaitingChoice:
                        FinalChoiceView(model: model)
                    case .completed, .interrupted:
                        Color.clear.onAppear { model.closeFlow() }
                    }
                } else {
                    Color.clear.onAppear { model.closeFlow() }
                }
            }
            .background(Theme.background.ignoresSafeArea())
        }
        .demoBanner(model.mode)
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

    /// 「答えずに進む」も選択肢の1つ。待機時間などの扱いは変わらない。
    private enum Choice: Hashable {
        case purpose(Purpose)
        case skip
    }

    @State private var selected: Choice?

    private func purpose(for choice: Choice) -> Purpose? {
        if case .purpose(let p) = choice { return p }
        return nil
    }

    var body: some View {
        CenteredScroll {
            VStack(spacing: 14) {
                FlowTitle(text: "今、どんなことに使いたいですか？")
                    .padding(.bottom, 10)
                ForEach(Purpose.allCases) { item in
                    ChoiceRow(isOn: selected == .purpose(item)) { selected = .purpose(item) } content: {
                        Text(item.label)
                    }
                }
                ChoiceRow(isOn: selected == .skip) { selected = .skip } content: {
                    Text("答えずに進む")
                }
                Button("ひと呼吸おく") {
                    if let selected { model.choosePurpose(purpose(for: selected)) }
                }
                .buttonStyle(FutoButtonStyle())
                .disabled(selected == nil)
                .padding(.top, 10)
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

    init(model: AppModel, session: Session) {
        self.model = model
        _controller = State(initialValue: WaitController(session: session, store: model.sessions))
    }

    private var timeText: String {
        let total = Int(controller.remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        CenteredScroll {
            VStack(spacing: 24) {
                FlowTitle(text: "少し、立ち止まってみましょう。")
                Text("画面を閉じると、止まります。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(breathing ? 0.16 : 0.08))
                        .padding(18)
                    Circle().stroke(Theme.softBlue, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: controller.progress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timeText)
                        .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                        .accessibilityLabel("残り \(Int(controller.remaining.rounded(.up))) 秒")
                }
                .frame(width: 200, height: 200)
                .padding(.vertical, 12)

                Button("ひと呼吸を終える") { model.endBreath() }
                    .buttonStyle(FutoTextButtonStyle())
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.closeFlow() } label: {
                    Label("ホームへ戻る", systemImage: "chevron.backward")
                }
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
        .onAppear {
            // ゆっくりした呼吸のような、ごく控えめな動き。視差・動きを減らす設定のときは動かさない。
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { breathing = true }
        }
        .onDisappear { controller.deactivate() }
    }
}

struct FinalChoiceView: View {
    let model: AppModel

    private var footnote: String {
        if model.canTemporarilyUnlock {
            return "「使いたい」を選ぶと、アプリを選んで少しだけ使えます。"
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
                Button("今はやめる") { model.finish(.deferred) }
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
            return "選んだアプリを使えます。約\(SharedState.unlockUsageMinutes)分使うか、\(until.formatted(date: .omitted, time: .shortened))になると、制限に戻ります。"
        case .failed:
            return "一時解除を始められなかったため、制限は続いています。"
        case .unsupported:
            return "この設定では、一時解除は使えません。使うには、ホームの「制限を終了」を押してください。"
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
                    Button("閉じる") { model.closeFlow() }
                        .buttonStyle(FutoButtonStyle())
                        .padding(.top, 12)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
