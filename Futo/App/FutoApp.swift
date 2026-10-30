import SwiftData
import SwiftUI

@main
struct FutoApp: App {
    private let container: ModelContainer
    @State private var model: AppModel
    @State private var sharing: SharingModel
    @State private var backup: BackupModel
    @Environment(\.scenePhase) private var scenePhase

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
        let sharing = SharingModel()
        _sharing = State(initialValue: sharing)
        _backup = State(initialValue: BackupModel(sharing: sharing, app: model))
        // 通知のタップを受け取る。起動前に設定して、起動を伴うタップも逃さない。
        NotificationService.shared.attach()
        NotificationService.shared.onRoute = { kind in model.handleNotificationTap(kind) }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .environment(sharing)
                .environment(backup)
                .onChange(of: scenePhase) { _, phase in
                    // アプリを開いたとき、継続共有を最新にする（常時同期ではない）
                    if phase == .active { Task { await sharing.refreshStanding(sessions: model.sessions.all(), mode: model.mode) } }
                }
                .task {
                    await sharing.loadProfile()
                    sharing.loadStandingConfigs()
                    await sharing.refreshStanding(sessions: model.sessions.all(), mode: model.mode)
                }
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
