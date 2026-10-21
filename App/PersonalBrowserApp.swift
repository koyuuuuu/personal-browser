import SwiftUI

@main
struct PersonalBrowserApp: App {
    @StateObject private var store = BrowserStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserRootView(store: store)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { store.flush() }
                }
        }
    }
}
