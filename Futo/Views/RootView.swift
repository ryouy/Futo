import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if model.onboardingDone {
                NavigationStack { HomeView(model: model) }
                    .fullScreenCover(isPresented: $model.showFlow) {
                        FlowView(model: model)
                    }
            } else {
                OnboardingView(model: model)
            }
        }
        .tint(Theme.accent)
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
