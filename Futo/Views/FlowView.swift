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
            VStack(alignment: .leading, spacing: 18) {
                Text("今、どんなことに使いたいですか？").font(.title2.weight(.medium))
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
                        .frame(minHeight: 58)
                        .padding(.horizontal, 20)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(selected == purpose ? Theme.accent : Theme.accent.opacity(0.10), lineWidth: selected == purpose ? 2 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected == purpose ? .isSelected : [])
                }
                Button("ひと呼吸おく") { model.choosePurpose(selected) }
                    .buttonStyle(FutoButtonStyle())
                    .disabled(selected == nil)
                Button("答えずに進む") { model.choosePurpose(nil) }
                    .buttonStyle(FutoTextButtonStyle())
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
        ScrollView {
            VStack(spacing: 24) {
                Text("少しだけ、立ち止まってみましょう。")
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
                Text("画面を閉じると、待機は一時停止します。")
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

                Button("この振り返りを終了") { model.endBreath() }
                    .buttonStyle(FutoTextButtonStyle())
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
            return "「使いたい」を選ぶと、使うアプリを選んで、一時的に使えるようにします（試験機能）。「今はやめる」では制限は続きます。"
        }
        if model.mode == .demo {
            return "デモでは、どちらを選んでも実際のアプリの制限は変わりません。"
        }
        return "この試作の設定では、どちらを選んでもアプリの制限は解除されません。"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("今も使いたいですか？").font(.title2.weight(.medium))
                Button("今はやめる") { model.finish(.deferred) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                Button("使いたい") { model.finish(.wantsToUse) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
                Text(footnote)
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

    private var wantsToUseMessage: String {
        switch model.unlockResult {
        case .started(let until):
            return "選んだアプリを一時的に使えるようにしました。選んだアプリの利用が約\(SharedState.unlockUsageMinutes)分に達するか、遅くとも\(until.formatted(date: .omitted, time: .shortened))までに、自動で制限に戻ります。ホームの「制限に戻す」でいつでも戻せます。"
        case .failed:
            return "利用したい気持ちを記録しました。一時解除を始められなかったため、制限は続いています。使う場合は、ホームの「制限を終了」から終了できます。"
        case .unsupported:
            return "利用したい気持ちを記録しました。この設定では一時解除は使えません。使う場合は、ホームの「制限を終了」から終了できます。"
        case nil:
            return model.mode == .demo
                ? "利用したい気持ちを記録しました。デモでは、実際のアプリの制限は変わりません。"
                : "利用したい気持ちを記録しました。制限は続いています。"
        }
    }

    var body: some View {
        if model.awaitingUnlockSelection {
            UnlockChooserView(model: model)
        } else {
            resultBody
        }
    }

    private var resultBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("記録しました。").font(.title2.weight(.medium))
                if outcome == .wantsToUse {
                    Text(wantsToUseMessage).lineSpacing(5)
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
