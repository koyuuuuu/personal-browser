import SwiftUI
import WebKit

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published private(set) var snapshot = BrowserSnapshot()
    @Published var notice: String?
    @Published var externalURL: URL?
    @Published private(set) var persistenceBlocked = false
    @Published private(set) var isClearingData = false
    let storage: SnapshotStore
    private var saveTask: Task<Void, Never>?
    static let maximumTabs = 12

    var selectedTab: BrowserTab? { tabs.first { $0.id == selectedID } }

    init() {
        let manager = FileManager.default
        let directory: URL
        #if DEBUG
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        #else
        let testing = false
        #endif
        if testing {
            directory = manager.temporaryDirectory.appendingPathComponent("BrowserUITests", isDirectory: true)
            try? manager.removeItem(at: directory)
        } else {
            directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PersonalBrowser", isDirectory: true)
        }
        storage = SnapshotStore(fileURL: directory.appendingPathComponent("browser.json"))
        do { snapshot = try storage.load() }
        catch {
            persistenceBlocked = true
            notice = "保存データを読み込めませんでした。元のファイルは保持しています。設定画面から退避・再作成できます。"
        }
        let records = snapshot.session.tabs
        if records.isEmpty {
            _ = newTab()
        } else {
            for record in records {
                _ = makeTab(id: record.id, url: record.url, isPrivate: false, select: false)
            }
            selectedID = snapshot.session.selectedID ?? tabs.first?.id
        }
        if testing { selectedTab?.loadTestFixture() }
    }

    @discardableResult
    func newTab(isPrivate: Bool = false, url: URL? = nil) -> BrowserTab? {
        guard !isClearingData else { return nil }
        return makeTab(url: url, isPrivate: isPrivate)
    }

    private func makeTab(id: UUID = UUID(), url: URL? = nil, isPrivate: Bool,
                         select: Bool = true, configuration: WKWebViewConfiguration? = nil) -> BrowserTab? {
        guard tabs.count < Self.maximumTabs else {
            notice = "タブは最大\(Self.maximumTabs)個です。使わないタブを閉じてください。"
            return nil
        }
        let tab = BrowserTab(id: id, isPrivate: isPrivate, configuration: configuration)
        tab.webView.allowsBackForwardNavigationGestures = snapshot.settings.swipeNavigation
        tab.onVisit = { [weak self, weak tab] url, title in
            guard let self, let tab else { return }
            self.snapshot.recordVisit(url: url, title: title, isPrivate: tab.isPrivate)
            self.scheduleSave()
        }
        tab.onStateChange = { [weak self] in self?.scheduleSave() }
        tab.onExternalURL = { [weak self] url in self?.externalURL = url }
        tab.onClose = { [weak self, weak tab] in
            if let tab { self?.close(tab) }
        }
        tab.onPopup = { [weak self] configuration, isPrivate in
            guard let self else { return nil }
            let popup = self.makeTab(isPrivate: isPrivate, configuration: configuration)
            popup?.hasContent = true
            return popup?.webView
        }
        tabs.append(tab)
        if select { selectedID = tab.id }
        if let url { tab.load(url) }
        scheduleSave()
        return tab
    }

    func select(_ tab: BrowserTab) {
        selectedID = tab.id
        scheduleSave()
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        tab.dispose()
        tabs.remove(at: index)
        if selectedID == tab.id {
            selectedID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        if tabs.isEmpty { _ = newTab() }
        scheduleSave()
    }

    func navigate(_ text: String) {
        guard !isClearingData else { return }
        do {
            let url = try AddressResolver.resolve(text, engine: snapshot.settings.searchEngine)
            selectedTab?.load(url)
        } catch { notice = error.localizedDescription }
    }

    func open(_ url: URL) {
        guard WebURLPolicy.allows(url), !isClearingData else { return }
        selectedTab?.load(url)
    }

    func addBookmark() {
        guard let tab = selectedTab, let url = tab.url, WebURLPolicy.allows(url) else { return }
        guard !snapshot.bookmarks.contains(where: { $0.url == url }) else {
            notice = "このページは保存済みです。"
            return
        }
        snapshot.bookmarks.append(Bookmark(title: tab.title, url: url))
        scheduleSave()
    }

    func deleteBookmarks(at offsets: IndexSet) {
        snapshot.bookmarks.remove(atOffsets: offsets)
        scheduleSave()
    }

    func clearHistory() {
        snapshot.history = []
        scheduleSave()
    }

    func updateSettings(_ settings: BrowserSettings) {
        snapshot.settings = settings.normalized()
        for tab in tabs {
            tab.webView.allowsBackForwardNavigationGestures = settings.swipeNavigation
        }
        scheduleSave()
    }

    func clearWebsiteData() {
        guard !isClearingData else { return }
        isClearingData = true
        let dataStores = [WKWebsiteDataStore.default()] + tabs.filter(\.isPrivate).map { $0.webView.configuration.websiteDataStore }
        for tab in tabs { tab.dispose() }
        tabs = []
        selectedID = nil
        Task { @MainActor in
            for dataStore in dataStores {
                await dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            }
            isClearingData = false
            _ = newTab()
            flush()
        }
    }

    func recoverStorage() {
        do {
            let original = storage.fileURL
            if FileManager.default.fileExists(atPath: original.path) {
                let backup = original.deletingLastPathComponent().appendingPathComponent("unreadable-\(UUID().uuidString).json")
                try FileManager.default.moveItem(at: original, to: backup)
            }
            persistenceBlocked = false
            flush()
        } catch { notice = error.localizedDescription }
    }

    private func captureSession() {
        let states = tabs.map { tab in
            let url = tab.url.flatMap { WebURLPolicy.allows($0) ? $0 : nil }
            return TabState(record: TabRecord(id: tab.id, url: url), isPrivate: tab.isPrivate)
        }
        snapshot.session = SessionSnapshot.capture(states, selectedID: selectedID)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            self?.flush()
        }
    }

    func flush() {
        saveTask?.cancel()
        guard !persistenceBlocked else { return }
        captureSession()
        do {
            try storage.save(snapshot)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: storage.fileURL.path)
        } catch {
            persistenceBlocked = true
            notice = "保存できませんでした。\(error.localizedDescription) 設定画面から保存先を再作成できます。"
        }
    }
}
