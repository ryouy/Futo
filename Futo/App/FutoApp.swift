import SwiftData
import SwiftUI

@main
struct FutoApp: App {
    private let container: ModelContainer
    @State private var model: AppModel

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Session.self)
        } catch {
            fatalError("記録の保存先を開けませんでした: \(error)")
        }
        self.container = container
        _model = State(initialValue: AppModel(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .modelContainer(container)
    }
}
