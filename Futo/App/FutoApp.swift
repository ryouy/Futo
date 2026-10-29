import SwiftData
import SwiftUI

@main
struct FutoApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var sharing = SharingModel()

    init() {
        LanguageStore.shared.applySystemDefaultIfUnset()
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Session.self, ReflectionCard.self)
        } catch {
            fatalError("記録の保存先を開けませんでした: \(error)")
        }
        self.container = container
        let model = AppModel(context: container.mainContext)
        _model = State(initialValue: model)
        // 通知のタップを受け取る。起動前に設定して、起動を伴うタップも逃さない。
        NotificationService.shared.attach()
        NotificationService.shared.onRoute = { kind in model.handleNotificationTap(kind) }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(sharing)
                .onOpenURL { sharing.handleIncoming(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { sharing.handleIncoming(url: url) }
                }
                .sheet(isPresented: Binding(get: { sharing.pendingInviteToken != nil }, set: { if !$0 { sharing.pendingInviteToken = nil } })) {
                    if let token = sharing.pendingInviteToken { InviteLandingView(token: token).environment(sharing) }
                }
        }
        .modelContainer(container)
    }
}
