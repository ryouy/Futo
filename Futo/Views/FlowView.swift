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

struct PurposeView: View {
    let model: AppModel
    @State private var selected: Purpose?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("今、どんなことに使いたいですか？").font(.title2.bold())
                ForEach(Purpose.allCases) { purpose in
                    Button {
                        selected = purpose
                    } label: {
                        HStack {
                            Text(purpose.label).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selected == purpose ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Theme.accent)
                        }
                        .frame(minHeight: 50)
                        .padding(.horizontal, 16)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(selected == purpose ? Theme.accent : .clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == purpose ? .isSelected : [])
                }
                Button("ひと呼吸おく") { model.choosePurpose(selected) }
                    .buttonStyle(FutoButtonStyle())
                    .disabled(selected == nil)
                Button("答えずに進む") { model.choosePurpose(nil) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
            .padding(20)
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

    init(model: AppModel, session: Session) {
        self.model = model
        _controller = State(initialValue: WaitController(session: session, store: model.sessions))
    }

    private var timeText: String {
        let total = Int(controller.remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("少しだけ、立ち止まってみましょう。")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("画面を閉じると、待機は一時停止します。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ZStack {
                    Circle().stroke(Theme.softBlue, lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: controller.progress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timeText)
                        .font(.system(size: 44, weight: .light).monospacedDigit())
                        .accessibilityLabel("残り \(Int(controller.remaining.rounded(.up))) 秒")
                }
                .frame(width: 200, height: 200)
                .padding(.vertical, 12)

                Button("この振り返りを終了") { model.endBreath() }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
            .padding(20)
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
        .onDisappear { controller.deactivate() }
    }
}

struct FinalChoiceView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("今も使いたいですか？").font(.title2.bold())
                Button("今はやめる") { model.finish(.deferred) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                Button("使いたい") { model.finish(.wantsToUse) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                Text("この試作では、どちらを選んでもアプリの制限は解除されません。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ResultView: View {
    let model: AppModel
    let outcome: SessionOutcome

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("記録しました。").font(.title2.bold())
                if outcome == .wantsToUse {
                    Text("利用したい気持ちを記録しました。この試作では、一時解除はまだできません。使う場合は、ホームの「制限を終了」から終了できます。")
                }
                Button("ホームへ") { model.closeFlow() }
                    .buttonStyle(FutoButtonStyle())
                    .padding(.top, 8)
            }
            .padding(20)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
