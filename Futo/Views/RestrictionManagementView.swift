import SwiftUI

/// 制限の管理。制限全体の一時停止と、制限の終了（恒久）を、ふだんの操作から分けて置く。
@MainActor
struct RestrictionManagementView: View {
    @Bindable var model: AppModel

    private var rules: PauseRules { model.pause.rules }

    var body: some View {
        Form {
            statusSection
            pauseSection
            endSection
        }
        .compactForm()
        .animation(.easeInOut(duration: 0.3), value: model.restriction)
        .animation(.easeInOut(duration: 0.3), value: model.intendsRestriction)
        .navigationTitle(tr("制限の管理"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 状態

    private var statusText: String {
        switch model.restriction {
        case .configured: return tr("制限中")
        case .temporarilyUnlocked: return tr("一時的に使えます")
        case .paused(let until): return tr("一時停止中（{0} に戻ります）", until.formatted(date: .omitted, time: .shortened))
        case .unverifiable: return tr("状態を確認できません")
        case .off: return tr("制限していません")
        }
    }

    private var statusSection: some View {
        CardSection { LabeledContent(tr("いまの状態"), value: statusText) }
    }

    // MARK: 一時停止

    private var pauseSection: some View {
        Group {
            CardSection {
                Text(tr("{0}待つと、{1}分間だけ、制限を停止できます。", durationText(seconds: rules.waitSeconds), "\(rules.pauseMinutes)"))
                    .font(.subheadline)
            }
            if model.isPaused {
                PrimarySection {
                    Button { model.resumeRestriction() } label: { Label(tr("制限を再開する"), systemImage: "lock.fill") }
                }
                CardSection {
                    NavigationLink { RestrictionWaitView(model: model, kind: .pause) } label: {
                        Label(tr("停止の時間を延ばす"), systemImage: "clock.arrow.circlepath").foregroundStyle(Theme.accent)
                    }.frame(minHeight: 44)
                }
            } else {
                CardSection {
                    if canPause {
                        NavigationLink { RestrictionWaitView(model: model, kind: .pause) } label: {
                            Label(tr("制限を一時停止"), systemImage: "pause.circle").foregroundStyle(Theme.accent)
                        }.frame(minHeight: 44)
                    } else {
                        Label(tr("制限を一時停止"), systemImage: "pause.circle").foregroundStyle(.secondary).frame(minHeight: 44)
                        Text(pauseUnavailableText).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var canPause: Bool {
        model.permission == .approved && model.restriction == .configured && model.device.supportsTemporaryUnlock
    }

    private var pauseUnavailableText: String {
        if !model.device.supportsTemporaryUnlock { return tr("この環境では、一時停止を使えません。") }
        if model.permission != .approved { return tr("Screen Timeの許可が必要です。") }
        return tr("制限がかかっているときに、使えます。")
    }

    // MARK: 終了（恒久）

    private var endSection: some View {
        CardSection {
            if model.intendsRestriction {
                Text(tr("{0}待つと、制限を終了できます。", durationText(seconds: rules.endWaitSeconds)))
                    .font(.subheadline)
                NavigationLink { RestrictionWaitView(model: model, kind: .end) } label: {
                    Label(tr("制限を終了する"), systemImage: "lock.open").foregroundStyle(.red)
                }
                .frame(minHeight: 44)
            } else {
                Text(tr("制限は、かかっていません。")).foregroundStyle(.secondary)
            }
        }
    }
}

/// 一時停止・制限の終了の待機。前面で表示している間だけ進む。待機中も、制限は外れない。
@MainActor
struct RestrictionWaitView: View {
    let model: AppModel
    let kind: WaitKind
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var started: Date?
    @State private var ended = false
    @State private var working = false

    private var pause: PauseFlow { model.pause }
    private var rules: PauseRules { pause.rules }
    private var isCurrentKind: Bool { pause.waitKind == kind }

    /// いまの段階（切り替えのアニメーションの目印）
    private var stage: String {
        if ended { return "ended" }
        if started != nil { return "done" }
        if isCurrentKind, pause.isReady { return "ready" }
        return isCurrentKind ? "waiting" : "loading"
    }

    private func timeText(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    var body: some View {
        CenteredScroll {
            // 段階が変わるときは、古い画面が先に薄れてから、新しい画面が現れる（ほかの画面と同じ、ゆるやかな切り替え）。
            ZStack {
                VStack(spacing: 20) {
                    if ended {
                        endedView
                    } else if let started {
                        done(until: started)
                    } else if isCurrentKind, pause.isReady {
                        ready
                    } else if isCurrentKind {
                        waiting
                    } else {
                        ProgressView()
                    }
                }
                .id(stage)
                .transition(.sequentialFade)
            }
            .animation(.easeInOut(duration: 0.3), value: stage)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isCurrentKind && started == nil && !ended)
        .task { if started == nil, !ended, !isCurrentKind { model.startWait(kind) } }
        .task(id: scenePhase) {
            // 前面にいる間だけ進む。バックグラウンド・画面ロックでは止まる。
            guard scenePhase == .active else { pause.deactivate(); return }
            pause.activate()
            // 長い待機の間、画面が自動で暗くならないようにする（ロックされると待機が止まるため）。この画面を離れたら戻す。
            UIApplication.shared.isIdleTimerDisabled = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                pause.tick()
            }
            pause.deactivate()
        }
        .onDisappear {
            pause.deactivate()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    // MARK: 段階

    private func stage(_ number: Int, _ title: String) -> some View {
        Text(tr("{0}/2　{1}", "\(number)", title))
            .font(.footnote.weight(.medium)).foregroundStyle(Theme.accent)
    }

    private var waiting: some View {
        VStack(spacing: 18) {
            stage(1, tr("待機中"))
            Text(tr("制限は、続いています。"))
                .font(.title3.weight(.medium))
            TimelineView(.animation(paused: scenePhase != .active)) { _ in
                let remaining = pause.liveRemaining()
                ZStack {
                    Circle().stroke(Theme.softBlue, lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: pause.liveProgress())
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(timeText(remaining))
                        .font(.system(size: 44, weight: .light, design: .rounded).monospacedDigit())
                        .accessibilityLabel(tr("残り {0} 秒", "\(Int(remaining.rounded(.up)))"))
                }
            }
            .frame(width: 200, height: 200)
            .padding(.vertical, 8)
            Text(tr("この画面を開いている間だけ、進みます。"))
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(tr("やめて、制限を続ける")) {
                pause.cancelWait()
                dismiss()
            }
            .buttonStyle(FutoButtonStyle(prominent: false))
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            stage(2, tr("確認"))
            Text(tr("待機が終わりました。"))
                .font(.title3.weight(.medium))
            Text(kind == .pause
                 ? tr("いまから{0}分間、制限を停止します。", "\(rules.pauseMinutes)")
                 : tr("制限そのものを終了します。"))
                .multilineTextAlignment(.center)
            if kind == .pause {
                Button(tr("{0}分間停止する", "\(rules.pauseMinutes)")) {
                    guard !working else { return }
                    working = true
                    if case .started(let until) = model.confirmPause() { started = until }
                    working = false
                }
                .buttonStyle(FutoButtonStyle())
                .disabled(working)
            } else {
                Button(tr("制限を終了する")) {
                    guard !working else { return }
                    working = true
                    if model.confirmEnd() { ended = true }
                    working = false
                }
                .buttonStyle(FutoButtonStyle())
                .disabled(working)
            }
            Button(tr("制限を続ける")) {
                pause.cancelWait()
                dismiss()
            }
            .buttonStyle(FutoButtonStyle(prominent: false))
        }
    }

    private func done(until: Date) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "pause.circle").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.accent)
            Text(tr("制限を停止しました。")).font(.title3.weight(.medium))
            Text(tr("{0} に、自動で制限に戻ります。", until.formatted(date: .omitted, time: .shortened)))
                .multilineTextAlignment(.center)
            Button(tr("閉じる")) { dismiss() }
                .buttonStyle(FutoButtonStyle())
        }
    }

    private var endedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.open").font(.system(size: 44, weight: .light)).foregroundStyle(Theme.accent)
            Text(tr("制限を終了しました。")).font(.title3.weight(.medium))
            Button(tr("閉じる")) { dismiss() }
                .buttonStyle(FutoButtonStyle())
        }
    }
}
