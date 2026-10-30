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
            .oneLine()
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
                FlowTitle(text: tr("今、どんなことに使いたいですか？"))
                Text(tr("このあと、{0}だけ立ち止まります。", "\(model.waitDurationText)"))
                    .oneLine(0.8)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
                ForEach(Purpose.allCases) { item in
                    ChoiceRow(isOn: selected == item, showsIndicator: false) { selected = item } content: {
                        Text(item.label).oneLine()
                    }
                }
                Button(tr("ひと呼吸おく")) { model.choosePurpose(selected) }
                    .buttonStyle(FutoButtonStyle())
                    .disabled(selected == nil)
                    .padding(.top, 10)
                Button(tr("答えずに進む")) { model.choosePurpose(nil) }
                    .buttonStyle(FutoButtonStyle(prominent: false))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { model.leavePurposeStep() } label: {
                    Label(tr("戻る"), systemImage: "chevron.backward")
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

    private func timeText(_ remaining: TimeInterval) -> String { countdownText(remaining) }

    var body: some View {
        CenteredScroll {
            VStack(spacing: 24) {
                FlowTitle(text: tr("少し、立ち止まってみましょう。"))
                Text(tr("{0}、ゆっくり息をしてみましょう。", "\(model.waitDurationText)"))
                    .oneLine(0.8)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                timer
                    .opacity(showTimer ? 1 : 0)
                    .padding(.vertical, 12)

                Button(tr("やめてホームへ")) { model.endBreath() }
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
            // タイマーが現れてから数え始める（10秒なら、10から始まる）
            while !showTimer, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(30)) }
            guard !Task.isCancelled else { return }
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
                    .accessibilityLabel(tr("残り {0} 秒", "\(Int(remaining.rounded(.up)))"))
            }
        }
        .frame(width: 200, height: 200)
    }
}

struct FinalChoiceView: View {
    let model: AppModel
    @State private var chosen: SessionOutcome?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 選んだことを少しの間だけ見せてから、次の画面へ（約0.3秒）。連打しても、記録は1回だけ。
    private func choose(_ outcome: SessionOutcome) {
        guard chosen == nil else { return }
        withAnimation(.easeInOut(duration: reduceMotion ? 0.15 : 0.2)) { chosen = outcome }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            model.finish(outcome)
        }
    }

    var body: some View {
        CenteredScroll {
            VStack(spacing: 16) {
                FlowTitle(text: tr("今も使いたいですか？"))
                    .padding(.bottom, 12)
                // 色で区別する。使う側は薄く、やめる側は濃く。どちらも同じ大きさで、押しやすさは変えない。
                // 選んだものは、色が入れ替わるように濃くなり、もう一方は薄くなる。
                Button(tr("使いたい")) { choose(.wantsToUse) }
                    .buttonStyle(FutoButtonStyle(prominent: chosen == .wantsToUse))
                    .opacity(chosen == nil || chosen == .wantsToUse ? 1 : 0.35)
                Button(tr("やめておく")) { choose(.deferred) }
                    .buttonStyle(FutoButtonStyle(prominent: chosen == nil || chosen == .deferred))
                    .opacity(chosen == nil || chosen == .deferred ? 1 : 0.35)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ResultView: View {
    let model: AppModel
    let outcome: SessionOutcome

    /// 見出しと本文。解除できたときは「解除しました」と、ひとこと添える。
    private var content: (title: String, lines: [String]) {
        if outcome == .deferred { return (tr("記録しました。"), []) }
        if model.isUnlocking { return (tr("解除しています…"), []) }
        switch model.unlockResult {
        case .started:
            let minutes = model.prefs.effectiveUnlockMinutes
            return (tr("解除しました"), [tr("{0}分ほど、ゆっくりどうぞ。", "\(minutes)"), tr("戻ってきたら、感想を教えてください。")])
        case .failed:
            return (tr("解除できませんでした"), [tr("制限は続いています。")])
        case .unsupported:
            return (tr("記録しました。"), [tr("この設定では、解除は使えません。")])
        case nil:
            return (tr("記録しました。"), [tr("制限は続いています。")])
        }
    }

    var body: some View {
        if model.awaitingUnlockSelection {
            UnlockChooserView(model: model)
        } else {
            CenteredScroll {
                VStack(spacing: 14) {
                    FlowTitle(text: content.title)
                    if model.isUnlocking {
                        ProgressView().padding(.vertical, 4)
                    }
                    ForEach(content.lines, id: \.self) { line in
                        Text(line).oneLine(0.8).foregroundStyle(.secondary)
                    }
                    Button(tr("ホームへ")) { model.closeFlow() }
                        .buttonStyle(FutoButtonStyle())
                        .disabled(model.isUnlocking)
                        .padding(.top, 14)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
