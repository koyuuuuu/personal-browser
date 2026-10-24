import SwiftUI

/// Preferences intentionally stay outside browser.json/schema 1, so app
/// downgrades never roll back or erase the latest library data.
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "updates.enabled") } }
    @Published var sourceAddress: String {
        didSet {
            defaults.set(sourceAddress, forKey: "updates.sourceURL")
            lastAutomaticAttempt = nil
            defaults.removeObject(forKey: "updates.lastAttempt")
            available = nil
            status = nil
        }
    }
    @Published private(set) var checking = false
    @Published private(set) var available: BrowserUpdate?
    @Published private(set) var status: String?
    @Published var dismissedVersion: String?
    private let defaults: UserDefaults
    private let session: URLSession
    private let testing: Bool
    private var lastAutomaticAttempt: Date?

    var shouldPresent: Bool {
        enabled && available != nil && dismissedVersion != available?.displayVersion
    }

    init(defaults: UserDefaults = .standard) {
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        let testing = false
        #endif
        self.testing = testing
        self.defaults = testing ? UserDefaults(suiteName: "BrowserUpdateUITests")! : defaults
        if testing { self.defaults.removePersistentDomain(forName: "BrowserUpdateUITests") }
        enabled = self.defaults.bool(forKey: "updates.enabled")
        sourceAddress = Bundle.main.infoDictionary?["BrowserUpdateSourceURL"] as? String ?? ""
        lastAutomaticAttempt = self.defaults.object(forKey: "updates.lastAttempt") as? Date
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func check(automatically: Bool = false) async {
        guard !checking else { return }
        if automatically {
            guard !testing, enabled, !sourceAddress.isEmpty,
                  lastAutomaticAttempt.map({ Date().timeIntervalSince($0) >= 86_400 }) ?? true else { return }
            lastAutomaticAttempt = Date()
            defaults.set(lastAutomaticAttempt, forKey: "updates.lastAttempt")
        }
        let url: URL
        do { url = try UpdateFeed.sourceURL(sourceAddress) }
        catch { status = "HTTPSのSideStoreソースURLを設定してください。"; return }
        guard let current = AppBuild(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") else { return }
        checking = true
        defer { checking = false }
        let originalAddress = sourceAddress
        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            // Stream with a limit instead of buffering an unbounded response.
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.expectedContentLength <= 1_048_576,
                  response.url?.scheme == "https" else { throw UpdateFeedError.invalidFeed }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 1_048_576 else { throw UpdateFeedError.invalidFeed }
                data.append(byte)
            }
            guard originalAddress == sourceAddress else { return }
            available = try UpdateFeed.available(in: data, current: current)
            status = available.map { "新しいバージョン \($0.displayVersion) があります。SideStoreで更新してください。" }
                ?? "この配信先に、現在より新しいバージョンはありません。"
        } catch {
            // URL errors can contain the secret source URL; never display or log them.
            guard originalAddress == sourceAddress else { return }
            status = "更新情報を取得できませんでした。接続とソースURLを確認してください。"
        }
    }

    func openSideStore() {
        // Opening SideStore does not install, delete, or replace any app.
        guard let url = URL(string: "sidestore://") else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            Task { @MainActor in
                if !opened { self?.status = "SideStoreをホーム画面から開いて更新してください。" }
            }
        }
    }
}
