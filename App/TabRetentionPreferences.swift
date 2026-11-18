import Combine
import Foundation

@MainActor
final class TabRetentionPreferences: ObservableObject {
    static let shared = TabRetentionPreferences()
    private static let key = "browser.tabs.residentLimit.v1"
    @Published private(set) var limit: Int
    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.key) as? Int
        limit = stored.map(TabRetentionPolicy.normalized) ?? TabRetentionPolicy.standardLimit
    }
    func setLimit(_ value: Int) {
        limit = TabRetentionPolicy.normalized(value)
        UserDefaults.standard.set(limit, forKey: Self.key)
    }
}
