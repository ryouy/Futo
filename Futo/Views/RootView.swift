import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.onboardingDone {
                ZStack {
                    NavigationStack { HomeView(model: model) }
                        .accessibilityHidden(model.showFlow)
                    if model.showFlow {
                        // 下からせり上がらず、ふわっと現れて、ふわっと消える。
                        FlowView(model: model)
                            .background(Theme.background.ignoresSafeArea())
                            .transition(.opacity.combined(with: .scale(scale: 0.97)))
                            .zIndex(1)
                    }
                }
                .animation(.easeInOut(duration: 0.6), value: model.showFlow)
            } else {
                OnboardingView(model: model)
            }
        }
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.5), value: ThemeStore.shared.color)
        .fontDesign(.rounded)
        .onChange(of: scenePhase) { _, phase in
            // 前面に戻るたびに、権限と本アプリの制限設定を再確認する。
            if phase == .active { model.refresh() }
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
