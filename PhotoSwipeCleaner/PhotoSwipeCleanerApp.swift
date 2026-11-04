import SwiftUI

@main
struct PhotoSwipeCleanerApp: App {
    @StateObject private var model = LibraryModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.refreshAccess()
            case .background: model.appDidEnterBackground()
            default: break
            }
        }
    }
}
