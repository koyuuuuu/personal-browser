import SwiftUI
import WebKit
import ImageIO

struct ClosedBrowserTab {
    var title: String
    var url: URL?
    var isPrivate: Bool
}

struct TabVisualTransition: Identifiable {
    let id = UUID()
    let direction: Int
    let outgoingImage: Data?
}

@MainActor
final class BrowserStore: ObservableObject {
    @Published private(set) var tabs: [BrowserTab] = []
    @Published var selectedID: UUID?
    @Published private(set) var snapshot = BrowserSnapshot()
    @Published private(set) var extras = LibraryExtras()
    @Published private(set) var features = FeaturePreferences()
    @Published var shareRequest: ShareRequest?
    @Published var messageRequest: ShareRequest?
    @Published var safariRequest: ShareRequest?
    @Published var saveLinkRequest: ShareRequest?
    @Published var connectionRequest: ConnectionRequest?
    @Published private(set) var connectionPreferences = ConnectionPreferences()
    private var connectionStorageBlocked = false
    private var ignoreChromeScrollUntil = Date.distantPast
    @Published var tabTransition: TabVisualTransition?
    @Published private(set) var presentation = PresentationPreferences()
    @Published private(set) var chromeVisible = true
    @Published private(set) var landscape = false
    private var chromeState = ChromeVisibility()
    private let previews: TabPreviewStore
    private var previewRecords: [UUID: TabPreviewRecord] = [:]
    private var previewStorageBlocked = false
    @Published private(set) var closedTabs: [ClosedBrowserTab] = []
    @Published var homeBackground: UIImage?
    @Published private(set) var extraStorageBlocked = false
    @Published var notice: String?
    @Published var externalURL: URL?
    @Published private(set) var persistenceBlocked = false
    @Published private(set) var isClearingData = false
    let storage: SnapshotStore
    private var saveTask: Task<Void, Never>?
    static let maximumTabs = 500
    private var activationOrder: [UUID] = []
    private var memoryObserver: NSObjectProtocol?
    private var restoring = true
    var directory: URL { storage.fileURL.deletingLastPathComponent() }
    var downloadDirectory: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true) }
    var downloadedFiles: [URL] { ((try? FileManager.default.contentsOfDirectory(at: downloadDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent } }

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
            if !ProcessInfo.processInfo.arguments.contains("--ui-keep-data") { try? manager.removeItem(at: directory) }
        } else {
            directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PersonalBrowser", isDirectory: true)
        }
        storage = SnapshotStore(fileURL: directory.appendingPathComponent("browser.json"))
        previews = TabPreviewStore(directory: directory.appendingPathComponent("tab-previews", isDirectory: true))
        do { previewRecords = Dictionary(uniqueKeysWithValues: try previews.records().map { ($0.id, $0) }) }
        catch { previewStorageBlocked = true }
        do { snapshot = try storage.load() }
        catch {
            persistenceBlocked = true
            notice = "保存データを読み込めませんでした。元のファイルは保持しています。設定画面から退避・再作成できます。"
        }
        loadAdditionalData()
        let records = snapshot.session.tabs
        if records.isEmpty {
            _ = newTab()
        } else {
            for record in records {
                _ = makeTab(id: record.id, url: record.url, isPrivate: false, select: false)
            }
            selectedID = snapshot.session.selectedID ?? tabs.first?.id
        }
        restoring = false
        if testing && !ProcessInfo.processInfo.arguments.contains("--ui-no-fixture") { selectedTab?.loadTestFixture() }
        #if DEBUG
        if testing, ProcessInfo.processInfo.arguments.contains("--ui-many-tabs") {
            for _ in 0..<18 { _ = newTab() }
            flush()
        }
        #endif
        memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.trimLiveTabs(limit: 1) }
        }
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
        tab.applyPreferences(features, swipe: snapshot.settings.swipeNavigation)
        tab.applyPresentation(presentation)
        tab.onVisit = { [weak self, weak tab] url, title in
            guard let self, let tab else { return }
            self.snapshot.recordVisit(url: url, title: title, isPrivate: tab.isPrivate)
            self.scheduleSave()
        }
        tab.onStateChange = { [weak self] in self?.scheduleSave() }
        tab.onVerticalScroll = { [weak self, weak tab] delta in
            guard let self, let tab, self.selectedID == tab.id else { return }
            self.scrollChrome(delta: Double(delta))
        }
        tab.onPreview = { [weak self, weak tab] image, url, title in
            guard let self, let tab, !tab.isPrivate, !self.previewStorageBlocked,
                  self.tabs.contains(where: { $0.id == tab.id }) else { return }
            do {
                if let record = try self.previews.save(id: tab.id, url: url, title: title, image: image, isPrivate: false) {
                    self.previewRecords[tab.id] = record
                    for file in [self.previews.directory, self.previews.directory.appendingPathComponent(record.fileName), self.previews.directory.appendingPathComponent("index.json")] {
                        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
                    }
                }
            } catch { self.previewStorageBlocked = true; self.notice = "タブ画像を保存できませんでした。既存の画像は保持しています。" }
        }
        tab.onConnectionRequest = { [weak self] request in self?.connectionRequest = request }
        tab.trustsCertificate = { [weak self] origin, fingerprint in self?.connectionPreferences.trusts(origin: origin, fingerprint: fingerprint) ?? false }
        tab.rememberCertificate = { [weak self] origin, fingerprint in
            guard let self else { return }
            do { try self.connectionPreferences.rememberCertificate(origin: origin, fingerprint: fingerprint); self.saveConnectionPreferences() }
            catch { self.notice = "証明書の例外を保存できませんでした。" }
        }
        tab.rememberHTTP = { [weak self] url in
            guard let self, let origin = ConnectionSecurity.origin(url), ConnectionSecurity.isLocal(url) else { return }
            if !self.connectionPreferences.httpOrigins.contains(origin) { self.connectionPreferences.httpOrigins.append(origin); self.saveConnectionPreferences() }
        }
        tab.onExternalURL = { [weak self] url in self?.externalURL = url }
        tab.onOpenLink = { [weak self] url, isPrivate in _ = self?.newTab(isPrivate: isPrivate, url: url) }
        tab.onShareLink = { [weak self] url in self?.shareRequest = ShareRequest(url: url) }
        tab.onAnalyzeLink = { [weak self] url in self?.openWatchHTML(url) }
        tab.onMessageLink = { [weak self] url in self?.messageRequest = ShareRequest(url: url) }
        tab.onSaveLink = { [weak self] url in self?.saveLinkRequest = ShareRequest(url: url) }
        tab.onOpenInSafari = { [weak self] url in self?.safariRequest = ShareRequest(url: url) }
        tab.onOpenInBrowser = { [weak self] url in self?.externalURL = url }
        tab.onDownload = { [weak self] _ in self?.notice = "ダウンロードしました。メニューの「ダウンロード」から共有・保存できます。" }
        tab.onClose = { [weak self, weak tab] in
            if let tab { self?.close(tab) }
        }
        tab.onPopup = { [weak self] configuration, isPrivate in
            guard let self else { return nil }
            let popup = self.makeTab(isPrivate: isPrivate, configuration: configuration)
            popup?.hasContent = true
            return popup?.webView
        }
        if let record = previewRecords[id], record.url == url { tab.title = record.title }
        tabs.append(tab)
        if select {
            if !restoring { beginTabTransition(direction: 1) }
            selectedTab?.capturePreview()
            selectedID = tab.id
            activationOrder.removeAll { $0 == tab.id }; activationOrder.append(tab.id)
        }
        if let url { tab.load(ConnectionSecurity.preferredURL(url, preferences: connectionPreferences)) }
        if !restoring { trimLiveTabs() }
        scheduleSave()
        return tab
    }

    func select(_ tab: BrowserTab) {
        // A drag can finish a tile's button action after that tile was removed.
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        if selectedID != tab.id {
            let old = tabs.firstIndex(where: { $0.id == selectedID }) ?? 0
            let next = tabs.firstIndex(where: { $0.id == tab.id }) ?? old
            beginTabTransition(direction: next >= old ? 1 : -1)
        }
        selectedTab?.capturePreview()
        selectedID = tab.id
        activationOrder.removeAll { $0 == tab.id }; activationOrder.append(tab.id)
        trimLiveTabs()
        scheduleSave()
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }) else { return }
        closedTabs.insert(ClosedBrowserTab(title: tab.title, url: tab.url, isPrivate: tab.isPrivate), at: 0)
        closedTabs = Array(closedTabs.prefix(20))
        tab.dispose()
        if !tab.isPrivate, !previewStorageBlocked {
            do { try previews.remove(id: tab.id); previewRecords.removeValue(forKey: tab.id) }
            catch { previewStorageBlocked = true }
        }
        tabs.remove(at: index)
        if selectedID == tab.id {
            selectedID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
        if tabs.isEmpty { _ = newTab() }
        scheduleSave()
    }

    func restoreClosedTab() {
        guard let record = closedTabs.first, tabs.count < Self.maximumTabs else { return }
        if let tab = newTab(isPrivate: record.isPrivate, url: record.url) { tab.title = record.title; closedTabs.removeFirst() }
    }

    func navigate(_ text: String) {
        guard !isClearingData else { return }
        do {
            let url = try AddressResolver.resolve(text, engine: snapshot.settings.searchEngine)
            selectedTab?.load(ConnectionSecurity.preferredURL(url, preferences: connectionPreferences))
        } catch { notice = error.localizedDescription }
    }

    func open(_ url: URL) {
        guard WebURLPolicy.allows(url), !isClearingData else { return }
        selectedTab?.load(ConnectionSecurity.preferredURL(url, preferences: connectionPreferences))
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
            tab.applyPreferences(features, swipe: settings.swipeNavigation)
        }
        scheduleSave()
    }

    func clearWebsiteData() {
        guard !isClearingData else { return }
        isClearingData = true
        closedTabs = []
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

    func switchTab(towardNext: Bool) {
        guard let current = tabs.firstIndex(where: { $0.id == selectedID }) else { return }
        switch TabNavigation.destination(current: current, count: tabs.count, towardNext: towardNext, maximum: Self.maximumTabs) {
        case .existing(let index): select(tabs[index])
        case .create: _ = newTab(isPrivate: selectedTab?.isPrivate ?? false)
        case .none: break
        }
    }

    private func beginTabTransition(direction: Int) {
        tabTransition = TabVisualTransition(direction: direction, outgoingImage: selectedTab?.previewData)
    }
    func setLandscape(_ value: Bool) {
        guard value != landscape else { return }
        landscape = value; chromeState.setLandscape(value); publishChrome()
    }
    func hideChrome() { chromeState.hide(); publishChrome() }
    func revealChrome() { chromeState.reveal(); publishChrome() }
    func scrollChrome(delta: Double) {
        guard Date() >= ignoreChromeScrollUntil else { return }
        chromeState.scroll(delta: delta); publishChrome()
    }
    private func publishChrome() {
        if chromeVisible != chromeState.visible { ignoreChromeScrollUntil = Date().addingTimeInterval(0.25); chromeVisible = chromeState.visible }
    }

    func loadPreview(_ tab: BrowserTab) {
        guard tab.previewData == nil, !tab.isPrivate, let record = previewRecords[tab.id], record.url == tab.url else { return }
        tab.previewData = try? previews.image(for: record)
    }
    func applicationBackgrounded() {
        selectedTab?.capturePreview()
        for tab in tabs { tab.prepareForBackground(continueAudio: presentation.backgroundAudio) }
        flush()
    }
    func applicationForegrounded() {
        for tab in tabs { tab.finishBackgroundPlayback() }
    }
    func updatePresentation(_ value: PresentationPreferences) {
        presentation = value.normalized()
        for tab in tabs { tab.applyPresentation(presentation) }
        saveAdditionalData()
    }

    private func trimLiveTabs(limit: Int? = nil) {
        let allowed = limit ?? features.maximumLiveTabs
        var live = tabs.filter(\.isLive)
        let candidates = live.filter { $0.id != selectedID && !$0.isProtectedForMedia }.sorted {
            (activationOrder.firstIndex(of: $0.id) ?? -1) < (activationOrder.firstIndex(of: $1.id) ?? -1)
        }
        for tab in candidates where live.count >= allowed {
            tab.suspend()
            live = tabs.filter(\.isLive)
        }
    }

    func openWatchHTML(_ url: URL) {
        do {
            // A previously visited tool can be reused without embedding the
            // user's private server hostname in a publicly distributed IPA.
            let recent = snapshot.history.first { item in item.url.scheme == "https" && ["/watch", "/watch.html"].contains(item.url.path.lowercased()) }?.url.absoluteString ?? ""
            let address = features.watchHTMLAddress.isEmpty ? recent : features.watchHTMLAddress
            let destination = try WatchHTML.destination(address: address, video: url)
            _ = newTab(isPrivate: selectedTab?.isPrivate ?? false, url: destination)
        } catch { notice = "設定 → ブラウザ機能で、HTTPSのWatch HTMLのURLを設定してください。" }
    }
    func analyzeCopiedLink() {
        let value = UIPasteboard.general.url ?? UIPasteboard.general.string.flatMap { URL(string: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let value, WebURLPolicy.allows(value) else { notice = "コピーしたHTTP・HTTPSのリンクが見つかりません。"; return }
        openWatchHTML(value)
    }
    func useCurrentWatchHTML() {
        guard let url = selectedTab?.url, url.scheme == "https", ["/watch", "/watch.html"].contains(url.path.lowercased()), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        parts.queryItems = parts.queryItems?.filter { $0.name != "url" }; parts.fragment = nil
        var prefs = features; prefs.watchHTMLAddress = parts.url?.absoluteString ?? ""; updateFeatures(prefs)
        notice = "このWatch HTMLを接続先に設定しました。"
    }

    func showHome() {
        // Keep any current media WebView alive; home is a new lightweight tab.
        _ = newTab(isPrivate: selectedTab?.isPrivate ?? false)
    }

    func updateFeatures(_ value: FeaturePreferences) {
        features = value
        features.favoriteColumns = min(6, max(3, value.favoriteColumns))
        features.maximumLiveTabs = min(8, max(2, value.maximumLiveTabs))
        for tab in tabs { tab.applyPreferences(features, swipe: snapshot.settings.swipeNavigation) }
        trimLiveTabs(); saveAdditionalData()
    }

    func addFavorite() {
        guard let tab = selectedTab, let url = tab.url, WebURLPolicy.allows(url) else { return }
        guard !extras.favorites.contains(where: { $0.url == url }) else { notice = "お気に入りに登録済みです。"; return }
        extras.favorites.append(Bookmark(title: tab.title, url: url)); saveAdditionalData()
    }
    func deleteFavorite(_ id: UUID) { extras.favorites.removeAll { $0.id == id }; saveAdditionalData() }
    func updateFavorite(_ item: Bookmark) {
        guard WebURLPolicy.allows(item.url), let index = extras.favorites.firstIndex(where: { $0.id == item.id }) else { return }
        extras.favorites[index] = item; saveAdditionalData()
    }
    func moveFavorite(_ id: UUID, by distance: Int) {
        guard let i = extras.favorites.firstIndex(where: { $0.id == id }) else { return }
        let j = i + distance; guard extras.favorites.indices.contains(j) else { return }
        extras.favorites.swapAt(i, j); saveAdditionalData()
    }
    func createFolder(name: String, parent: UUID?) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        extras.folders.append(BookmarkFolder(name: value, parentID: parent)); saveAdditionalData()
    }
    func updateFolder(_ item: BookmarkFolder) {
        guard !item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              extras.canMoveFolder(item.id, to: item.parentID), let i = extras.folders.firstIndex(where: { $0.id == item.id }) else { notice = "フォルダを自分自身の中に移動できません。"; return }
        extras.folders[i] = item; saveAdditionalData()
    }
    func deleteFolder(_ id: UUID) { extras.removeFolder(id); saveAdditionalData() }
    func moveFolders(_ ids: [UUID], source: IndexSet, destination: Int) {
        var visible = extras.folders.filter { ids.contains($0.id) }
        visible.move(fromOffsets: source, toOffset: destination)
        var iterator = visible.makeIterator()
        for index in extras.folders.indices where ids.contains(extras.folders[index].id) { extras.folders[index] = iterator.next()! }
        saveAdditionalData()
    }
    func moveBookmark(_ id: UUID, folder: UUID?) { extras.bookmarkFolders[id.uuidString] = folder; saveAdditionalData() }
    func updateBookmark(_ bookmark: Bookmark) {
        guard WebURLPolicy.allows(bookmark.url), let i = snapshot.bookmarks.firstIndex(where: { $0.id == bookmark.id }) else { return }
        snapshot.bookmarks[i] = bookmark; scheduleSave()
    }
    func deleteBookmark(_ id: UUID) {
        snapshot.bookmarks.removeAll { $0.id == id }; extras.bookmarkFolders.removeValue(forKey: id.uuidString)
        scheduleSave(); saveAdditionalData()
    }
    func reorderBookmarks(_ ids: [UUID], source: IndexSet, destination: Int) {
        var visible = snapshot.bookmarks.filter { ids.contains($0.id) }; visible.move(fromOffsets: source, toOffset: destination)
        var iterator = visible.makeIterator()
        for index in snapshot.bookmarks.indices where ids.contains(snapshot.bookmarks[index].id) { snapshot.bookmarks[index] = iterator.next()! }
        scheduleSave()
    }

    func importPages(_ pages: [ImportedPage], kind: LibraryImportKind) -> Int {
        var count = 0
        var bookmarkURLs = Set(snapshot.bookmarks.map(\.url))
        var favoriteURLs = Set(extras.favorites.map(\.url))
        var historyURLs = Set(snapshot.history.map(\.url))
        for page in pages {
            switch kind {
            case .bookmarks:
                guard bookmarkURLs.insert(page.url).inserted else { continue }
                let bookmark = Bookmark(title: page.title, url: page.url)
                snapshot.bookmarks.append(bookmark)
                var parent: UUID?
                for name in page.folders {
                    if let folder = extras.folders.first(where: { $0.name == name && $0.parentID == parent }) { parent = folder.id }
                    else { let folder = BookmarkFolder(name: name, parentID: parent); extras.folders.append(folder); parent = folder.id }
                }
                extras.bookmarkFolders[bookmark.id.uuidString] = parent
            case .favorites:
                guard favoriteURLs.insert(page.url).inserted else { continue }
                extras.favorites.append(Bookmark(title: page.title, url: page.url))
            case .history:
                guard historyURLs.insert(page.url).inserted else { continue }
                snapshot.history.append(HistoryEntry(title: page.title, url: page.url, visitedAt: page.date))
            }
            count += 1
        }
        snapshot.history.sort { $0.visitedAt > $1.visitedAt }; snapshot.history = Array(snapshot.history.prefix(1000))
        flush(); return count
    }

    func setHomeBackground(_ data: Data?) {
        let file = directory.appendingPathComponent("home-background.jpg")
        do {
            if let data {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1800,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return }
                let compressed = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.8)
                guard let compressed else { return }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try compressed.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                homeBackground = UIImage(data: compressed)
            } else { if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }; homeBackground = nil }
        } catch { notice = "背景画像を保存できませんでした。" }
    }

    private func loadAdditionalData() {
        do {
            let file = directory.appendingPathComponent("library-extras.json")
            if FileManager.default.fileExists(atPath: file.path) { extras = try JSONDecoder().decode(LibraryExtras.self, from: Data(contentsOf: file)).validated() }
            let prefs = directory.appendingPathComponent("features.json")
            if FileManager.default.fileExists(atPath: prefs.path) { features = try JSONDecoder().decode(FeaturePreferences.self, from: Data(contentsOf: prefs)) }
            let securityFile = directory.appendingPathComponent("security-exceptions.json")
            if FileManager.default.fileExists(atPath: securityFile.path) {
                do { connectionPreferences = try JSONDecoder().decode(ConnectionPreferences.self, from: Data(contentsOf: securityFile)) }
                catch { connectionStorageBlocked = true }
            }
            let presentationFile = directory.appendingPathComponent("presentation.json")
            if FileManager.default.fileExists(atPath: presentationFile.path) { presentation = try JSONDecoder().decode(PresentationPreferences.self, from: Data(contentsOf: presentationFile)) }
            homeBackground = UIImage(contentsOfFile: directory.appendingPathComponent("home-background.jpg").path)
        } catch { extraStorageBlocked = true; notice = "追加データを読み込めませんでした。元のファイルを保持し、上書きを停止しています。" }
    }
    private func saveAdditionalData() {
        guard !extraStorageBlocked, !persistenceBlocked else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(extras).write(to: directory.appendingPathComponent("library-extras.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try encoder.encode(features).write(to: directory.appendingPathComponent("features.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try encoder.encode(presentation).write(to: directory.appendingPathComponent("presentation.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { extraStorageBlocked = true; notice = "追加データを保存できませんでした。空き容量を確認してください。" }
    }

    func removeConnectionException(_ origin: String) {
        connectionPreferences.certificates.removeValue(forKey: origin)
        connectionPreferences.httpOrigins.removeAll { $0 == origin }
        saveConnectionPreferences()
    }
    private func saveConnectionPreferences() {
        guard !connectionStorageBlocked else { notice = "接続例外の保存を停止しています。既存ファイルは保持しています。"; return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(connectionPreferences).write(to: directory.appendingPathComponent("security-exceptions.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { notice = "接続例外を保存できませんでした。今回は接続しても、次回は再確認します。" }
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
            saveAdditionalData()
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: storage.fileURL.path)
        } catch {
            persistenceBlocked = true
            notice = "保存できませんでした。\(error.localizedDescription) 設定画面から保存先を再作成できます。"
        }
    }
}
