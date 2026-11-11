import AppTrackingTransparency
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AdsService.self) private var ads
    @Environment(SharingModel.self) private var sharing
    /// 起動時に約1秒、スプラッシュを見せる。
    @State private var showSplash = true

    /// スプラッシュ・初回説明と同じ緑。
    private let introGreen = Color(red: 25 / 255, green: 100 / 255, blue: 89 / 255)

    private var canShowOverlays: Bool {
        model.onboardingDone && model.tutorialCompleted && model.tutorialStep == nil && !showSplash && !model.showFlow
            && !model.lockSealActive
    }

    /// 広告の同意（UMP → ATT）を求めてよい状況：前面で、スプラッシュ・初回説明・チュートリアル・Screen Timeの許可・通知の確認が済み、
    /// ホームが操作できて、ほかのダイアログ・画面が出ていない。
    private var shouldAskAdConsent: Bool {
        !DemoConfig.isOn && scenePhase == .active && !showSplash && model.canAskAdConsent
    }

    /// 開いたときに出す振り返り。スプラッシュ・説明・チュートリアル・ひと呼吸の最中は出さない。
    private var reflectionToShow: ReflectionCard? {
        canShowOverlays ? model.visibleCards.first : nil
    }

    /// 一時解除のあとの感想。朝夜の振り返りが出ていないときに出す。
    private var questionToShow: Session? {
        canShowOverlays && reflectionToShow == nil ? model.pendingReflection : nil
    }

    var body: some View {
        ZStack {
            (model.onboardingDone ? Theme.background : LinearGradient(colors: [introGreen, introGreen], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            if model.onboardingDone {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    // ひと呼吸の画面が出る間はホームを先に消し、戻るときは画面が消えてからホームを出す。
                    NavigationStack { HomeView(model: model) }
                        .readableColumn()
                        .opacity(model.showFlow ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2).delay(model.showFlow ? 0 : 0.2), value: model.showFlow)
                        .accessibilityHidden(model.showFlow)
                    if model.showFlow {
                        FlowView(model: model)
                            .readableColumn()
                            .background(Theme.background.ignoresSafeArea())
                            .transition(.sequentialFade)
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: model.showFlow)
                .transition(.opacity)
            } else {
                OnboardingView(model: model)
                    .readableColumn()
                    .transition(.opacity)
            }
        }
        // 説明（緑）からホームへは、間に下地が見えないよう、ゆっくり溶けるように切り替える。
        .animation(.easeInOut(duration: 1.0), value: model.onboardingDone)
        .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
            if model.tutorialStep != nil {
                TutorialOverlay(model: model, anchors: anchors)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeInOut(duration: 0.9)),
                        removal: .opacity.animation(.easeInOut(duration: 0.3))))
            }
        }
        .animation(.easeInOut(duration: 0.9), value: model.tutorialStep != nil)
        .overlay {
            if let card = reflectionToShow {
                ReflectionOverlay(card: card) { model.dismissCard(card) }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: reflectionToShow?.key)
        .overlay {
            if let session = questionToShow {
                ReflectionQuestionOverlay { model.answerReflection(session, $0) }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: questionToShow?.id)
        .overlay {
            if ads.isShowingTrackingExplainer {
                TrackingExplainerOverlay { ads.dismissTrackingExplainer() }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: ads.isShowingTrackingExplainer)
        #if DEBUG
        // 開発用：確かめたい画面を引数で指定したときは、はじめの説明を済ませた状態にする
        .task {
            if let screen = DebugLaunch.screen, screen != "onboarding", !model.onboardingDone { model.completeOnboarding(mode: .device) }
            if DebugLaunch.showTrackingExplainer { ads.debugShowTrackingExplainer() }
            if DebugLaunch.enterDemo { await sharing.enterDemo() }
            if DebugLaunch.askAdConsentNow {
                try? await Task.sleep(for: .milliseconds(2500))
                ads.startConsentFlowIfNeeded()
            }
        }
        #endif
        #if DEBUG
        // 開発用：広告の同意の流れの状況を、Xcodeのコンソールに出す（実機で、説明画面が出ない理由を調べる用）
        .task(id: model.adConsentBlockers) {
            NSLog("[AdConsent] blockers=%@ ATT=%ld splash=%@ active=%@", model.adConsentBlockers.isEmpty ? "なし" : model.adConsentBlockers.joined(separator: " / "),
                  ATTrackingManager.trackingAuthorizationStatus.rawValue, showSplash ? "true" : "false", scenePhase == .active ? "true" : "false")
        }
        #endif
        .task(id: shouldAskAdConsent) {
            // 状況が落ち着いてから、少し置いて始める（置いている間に条件が崩れたら、取り消される）
            guard shouldAskAdConsent else { return }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled, shouldAskAdConsent else { return }
            ads.startConsentFlowIfNeeded()
        }
        .task(id: model.onboardingDone) {
            // ホームが現れてから、初回（または説明の見直しのあと）だけチュートリアルを始める。
            guard model.onboardingDone, !model.tutorialCompleted else { return }
            try? await Task.sleep(for: .milliseconds(1900))
            model.startTutorialIfNeeded()
        }
        .overlay {
            if showSplash {
                SplashView().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeInOut(duration: 0.8)) { showSplash = false }
        }
        .tint(Theme.accentText)
        // シートを開いて、ホームが小さくなったとき、後ろがテーマ色になるように（黒くしない）
        .background(WindowBackgroundSetter(color: Theme.windowBackgroundUIColor))
        .environment(\.locale, LanguageStore.shared.language.locale)
        .foregroundStyle(Theme.text)
        .animation(.easeInOut(duration: 0.23), value: ThemeStore.shared.selectionKey)
        .fontDesign(.rounded)
        .onChange(of: scenePhase) { _, phase in
            // 前面に戻るたびに、権限と本アプリの制限設定を再確認する。
            if phase == .active { model.didBecomeActive() }
        }
        .alert(tr("通知を受け取りますか？"), isPresented: $model.showNotificationPrimer) {
            Button(tr("次へ")) { model.requestNotificationPermission(enableDefaults: true) }
            Button(tr("今はしない"), role: .cancel) { model.declineNotificationPrimer() }
        } message: {
            Text(tr("朝と夜の振り返りをお知らせします\nあとから、設定でいつでも変えられます\n許可しなくても、ほかの機能は使えます"))
        }
        .alert(tr("お知らせ"), isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button(tr("閉じる"), role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
