import SwiftUI

@main
struct PersonalBrowserApp: App {
    @StateObject private var store = BrowserStore()
    @StateObject private var updates = UpdateChecker()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            BrowserRootView(store: store)
                .environmentObject(updates)
                .onOpenURL { store.receiveExternalURL($0) }
                .task { await updates.check(automatically: true) }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { store.applicationBackgrounded() }
                    else { store.applicationForegrounded(); Task { await updates.check(automatically: true) } }
                }
        }
    }
}
