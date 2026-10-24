import SwiftUI
import WebKit

struct ShareRequest: Identifiable {
    let id = UUID()
    let url: URL
}

enum BrowserSheet: Identifiable {
    case tabs, bookmarks, history, settings, downloads
    case share(ShareRequest)
    var id: String {
        switch self {
        case .tabs: "tabs"; case .bookmarks: "bookmarks"; case .history: "history"
        case .settings: "settings"; case .downloads: "downloads"; case .share(let payload): "share-" + payload.id.uuidString
        }
    }
}

@MainActor
struct BrowserRootView: View {
    @EnvironmentObject private var updates: UpdateChecker
    @ObservedObject var store: BrowserStore
    @State private var sheet: BrowserSheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let tab = store.selectedTab {
                TabBrowserView(store: store, tab: tab, showSheet: { sheet = $0 }, share: share)

            } else {
                ProgressView("Webサイトデータを消去中…")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if updates.shouldPresent, let update = updates.available {
                HStack {
                    Text("新しいバージョン \(update.displayVersion)").font(.callout)
                    Spacer()
                    Button("SideStore") { updates.openSideStore() }
                    Button("閉じる", systemImage: "xmark") { updates.dismissedVersion = update.displayVersion }
                        .labelStyle(.iconOnly)
                }
                .padding(10).background(.thinMaterial)
            }
        }
        .tint(store.selectedTab?.isPrivate == true ? .purple : .blue)
        .sheet(item: $sheet) { route in
            switch route {
            case .tabs: TabsView(store: store)
            case .bookmarks: LibraryView(store: store, showHistory: false)
            case .history: LibraryView(store: store, showHistory: true)
            case .settings: SettingsView(store: store)
            case .downloads: DownloadsView(store: store)
            case .share(let payload): ActivityView(items: [payload.url])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeBrowserLibrary)) { _ in sheet = nil }
        .onChange(of: store.shareRequest?.id) { _, _ in
            if let payload = store.shareRequest { sheet = .share(payload) }
        }
        .overlay(alignment: .top) {
            if store.tabAddedID != nil {
                Label("タブを追加しました（\(store.tabs.count)）", systemImage: "plus.square.on.square")
                    .font(.callout.bold()).padding(12).background(.regularMaterial, in: Capsule())
                    .padding(.top, 8).allowsHitTesting(false)
                    .accessibilityIdentifier("tabAddedNotice")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(store.features.animateNewTabs && !reduceMotion ? .snappy(duration: 0.25) : nil, value: store.tabAddedID)
        .task(id: store.tabAddedID) {
            guard store.tabAddedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.3))
            if !Task.isCancelled { store.tabAddedID = nil }
        }
        .alert("お知らせ", isPresented: Binding(
            get: { store.notice != nil },
            set: { if !$0 { store.notice = nil } }
        )) {
            Button("OK", role: .cancel) { store.notice = nil }
        } message: { Text(store.notice ?? "") }
        .confirmationDialog("別のアプリで開きますか？", isPresented: Binding(
            get: { store.externalURL != nil },
            set: { if !$0 { store.externalURL = nil } }
        ), titleVisibility: .visible, presenting: store.externalURL) { url in
            Button("開く") {
                UIApplication.shared.open(url)
                store.externalURL = nil
            }
            Button("キャンセル", role: .cancel) { store.externalURL = nil }
        } message: { url in Text(url.absoluteString) }
    }

    private func share() {
        guard let url = store.selectedTab?.url, WebURLPolicy.allows(url) else { return }
        sheet = .share(ShareRequest(url: url))
    }
}

@MainActor
struct TabBrowserView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let showSheet: (BrowserSheet) -> Void
    let share: () -> Void
    @State private var address = ""
    @State private var promptText = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if store.snapshot.settings.toolbarPosition == .top { chrome }
            if tab.isPrivate {
                Label("プライベート · 履歴とタブを端末に保存しません", systemImage: "hand.raised")
                    .font(.caption).foregroundStyle(.purple)
                    .frame(maxWidth: .infinity).padding(8)
                    .background(Color.purple.opacity(0.08))
            }
            if let error = tab.errorMessage {
                HStack(alignment: .top) {
                    Text(error).font(.callout)
                    Spacer()
                    Button("閉じる", systemImage: "xmark") { tab.errorMessage = nil }
                        .labelStyle(.iconOnly)
                }
                .padding().background(Color.orange.opacity(0.12))
            }
            ZStack {
                WebSurface(store: store)
                    .accessibilityIdentifier("webContent")
                    .accessibilityHidden(!tab.hasContent)
                if !tab.hasContent { HomePageView(store: store, isPrivate: tab.isPrivate) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if store.snapshot.settings.toolbarPosition == .bottom { chrome }
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear { address = tab.url?.absoluteString ?? "" }
        .onChange(of: tab.id) { _, _ in address = tab.url?.absoluteString ?? ""; addressFocused = false }
        .onChange(of: tab.url) { _, url in
            if !addressFocused { address = url?.absoluteString ?? "" }
        }
        .onChange(of: addressFocused) { _, focused in
            if !focused { address = tab.url?.absoluteString ?? "" }
        }
        .onChange(of: tab.dialog?.id) { _, _ in promptText = tab.dialog?.defaultText ?? "" }
        .onDisappear {
            tab.dialog?.resolve(nil)
            tab.dialog = nil
        }
        .alert("Webページからのメッセージ", isPresented: Binding(
            get: { tab.dialog != nil },
            set: { if !$0 { finishDialog(nil) } }
        ), presenting: tab.dialog) { dialog in
            if dialog.kind == .prompt { TextField("入力", text: $promptText) }
            Button("OK") { finishDialog(dialog.kind == .prompt ? promptText : "OK") }
            if dialog.kind != .alert {
                Button("キャンセル", role: .cancel) { finishDialog(nil) }
            }
        } message: { dialog in Text(dialog.message) }
    }

    private var chrome: some View {
        VStack(spacing: 4) {
            if tab.isLoading { ProgressView(value: tab.progress).tint(.blue) }
            HStack(spacing: 8) {
                Image(systemName: tab.url?.scheme == "http" ? "exclamationmark.circle" : "globe")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(tab.url?.scheme == "http" ? "HTTP接続" : "アドレス")
                TextField("URLまたは検索語", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .accessibilityIdentifier("addressField")
                    .onSubmit {
                        let input = address
                        addressFocused = false
                        store.navigate(input)
                    }
                if addressFocused {
                    Button("入力を消去", systemImage: "xmark.circle.fill") { address = "" }
                        .labelStyle(.iconOnly).foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 35).onEnded { value in
                guard store.features.swipeAddressToSwitchTabs, !addressFocused,
                      abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                store.switchTab(towardNext: value.translation.width < 0)
            })
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 8)
            HStack(spacing: 0) {
                ForEach(store.snapshot.settings.actions) { action in
                    Button { perform(action) } label: {
                        Image(systemName: action == .reload && tab.isLoading ? "xmark" : action.symbol)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityLabel(action == .reload && tab.isLoading ? "読み込みを停止" : action.label)
                    .accessibilityIdentifier(action.rawValue + "Button")
                    .disabled(disabled(action))
                }
                Menu {
                    Button("新しいタブ", systemImage: "plus") { _ = store.newTab() }
                    Button("新しいプライベートタブ", systemImage: "hand.raised") { _ = store.newTab(isPrivate: true) }
                    Button("タブ一覧", systemImage: "square.on.square") { showSheet(.tabs) }
                    Button("ホーム", systemImage: "house") { store.showHome() }
                    Divider()
                    Button("お気に入りに追加", systemImage: "star") { store.addFavorite() }
                        .disabled(tab.url.map { !WebURLPolicy.allows($0) } ?? true)
                    Button("ブックマークに追加", systemImage: "bookmark") { store.addBookmark() }
                        .disabled(tab.url.map { !WebURLPolicy.allows($0) } ?? true)
                    Button("ブックマーク", systemImage: "book") { showSheet(.bookmarks) }
                    Button("履歴", systemImage: "clock") { showSheet(.history) }
                    Button("共有", systemImage: "square.and.arrow.up", action: share)
                        .disabled(tab.url.map { !WebURLPolicy.allows($0) } ?? true)
                    Button("ページ内を検索", systemImage: "magnifyingglass") {
                        tab.webView.findInteraction?.presentFindNavigator(showingReplace: false)
                    }.disabled(!tab.hasContent)
                    Button("ダウンロード", systemImage: "arrow.down.circle") { showSheet(.downloads) }
                    Divider()
                    Button("設定", systemImage: "slider.horizontal.3") { showSheet(.settings) }
                } label: {
                    Label("メニュー", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("menuButton")
            }
            .font(.system(size: 20))
            .padding(.horizontal, 4)
        }
        .padding(.top, 6)
        .background(.regularMaterial)
    }

    private func disabled(_ action: BrowserAction) -> Bool {
        switch action {
        case .back: !tab.canGoBack
        case .forward: !tab.canGoForward
        case .reload: !tab.hasContent
        case .share: tab.url.map { !WebURLPolicy.allows($0) } ?? true
        default: false
        }
    }

    private func perform(_ action: BrowserAction) {
        addressFocused = false
        switch action {
        case .back: tab.webView.goBack()
        case .forward: tab.webView.goForward()
        case .reload:
            if tab.isLoading { tab.webView.stopLoading() }
            else if tab.webView.url != nil { tab.webView.reload() }
            else if let url = tab.url { tab.load(url) }
        case .newTab: _ = store.newTab()
        case .tabs: showSheet(.tabs)
        case .bookmarks: showSheet(.bookmarks)
        case .share: share()
        }
    }

    private func finishDialog(_ value: String?) {
        let dialog = tab.dialog
        tab.dialog = nil
        dialog?.resolve(value)
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.view.accessibilityIdentifier = "shareSheet"
        if let popover = controller.popoverPresentationController {
            popover.sourceView = controller.view
            popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
        }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
