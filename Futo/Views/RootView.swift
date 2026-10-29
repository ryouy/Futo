import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    /// 起動時に約1秒、スプラッシュを見せる。
    @State private var showSplash = true

    var body: some View {
        Group {
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
            } else {
                OnboardingView(model: model)
            }
        }
        .overlay {
            if showSplash {
                SplashView().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(1000))
            withAnimation(.easeInOut(duration: 0.4)) { showSplash = false }
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
