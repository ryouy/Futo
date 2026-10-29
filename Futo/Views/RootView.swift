import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// 起動時に約1秒、スプラッシュを見せる。
    @State private var showSplash = true

    /// スプラッシュ・初回説明と同じ緑。
    private let introGreen = Color(red: 25 / 255, green: 100 / 255, blue: 89 / 255)

    var body: some View {
        ZStack {
            (model.onboardingDone ? Theme.background : LinearGradient(colors: [introGreen, introGreen], startPoint: .top, endPoint: .bottom))
                .ignoresSafeArea()
            if model.onboardingDone {
                ZStack {
                    Theme.background.ignoresSafeArea()
                    // ひと呼吸の画面が出る間はホームを先に消し、戻るときは画面が消えてからホームを出す。
                    NavigationStack { HomeView(model: model) }
                        .opacity(model.showFlow ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2).delay(model.showFlow ? 0 : 0.2), value: model.showFlow)
                        .accessibilityHidden(model.showFlow)
                    if model.showFlow {
                        FlowView(model: model)
                            .background(Theme.background.ignoresSafeArea())
                            .transition(.sequentialFade)
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: model.showFlow)
                .transition(.opacity)
            } else {
                OnboardingView(model: model)
                    .transition(.opacity)
            }
        }
        // 説明（緑）からホームへは、間に下地が見えないよう、ゆっくり溶けるように切り替える。
        .animation(.easeInOut(duration: 1.0), value: model.onboardingDone)
        .overlayPreferenceValue(TutorialAnchorKey.self) { anchors in
            if model.tutorialStep != nil {
                TutorialOverlay(model: model, anchors: anchors)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.tutorialStep != nil)
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
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.3), value: ThemeStore.shared.color)
        .fontDesign(.rounded)
        .onChange(of: scenePhase) { _, phase in
            // 前面に戻るたびに、権限と本アプリの制限設定を再確認する。
            if phase == .active { model.didBecomeActive() }
        }
        .alert("お知らせ", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
