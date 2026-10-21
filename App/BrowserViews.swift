import SwiftUI
import WebKit

enum BrowserSheet: String, Identifiable {
    case tabs, bookmarks, history, settings, share
    var id: String { rawValue }
}

@MainActor
struct BrowserRootView: View {
    @ObservedObject var store: BrowserStore
    @State private var sheet: BrowserSheet?
    @State private var sharingURL: URL?

    var body: some View {
        Group {
            if let tab = store.selectedTab {
                TabBrowserView(store: store, tab: tab, showSheet: { sheet = $0 }, share: share)
                    .id(tab.id)
            } else {
                ProgressView("Webサイトデータを消去中…")
            }
        }
        .tint(store.selectedTab?.isPrivate == true ? .purple : .blue)
        .sheet(item: $sheet) { route in
            switch route {
            case .tabs: TabsView(store: store)
            case .bookmarks: LibraryView(store: store, showHistory: false)
            case .history: LibraryView(store: store, showHistory: true)
            case .settings: SettingsView(store: store)
            case .share:
                if let sharingURL { ActivityView(items: [sharingURL]) }
            }
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
        sharingURL = url
        sheet = .share
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
            if tab.hasContent {
                WebViewHost(webView: tab.webView)
                    .accessibilityIdentifier("webContent")
            } else {
                startPage
            }
            if store.snapshot.settings.toolbarPosition == .bottom { chrome }
        }
        .background(Color(uiColor: .systemBackground))
        .onAppear { address = tab.url?.absoluteString ?? "" }
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

    private var startPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Image(systemName: tab.isPrivate ? "hand.raised.circle" : "globe.asia.australia")
                    .font(.system(size: 52)).foregroundStyle(tab.isPrivate ? .purple : .blue)
                Text(tab.isPrivate ? "プライベートブラウズ" : "あなたのブラウザ")
                    .font(.largeTitle.bold())
                Text("アドレス欄にURLや検索語を入力して始めましょう。")
                    .foregroundStyle(.secondary)
                if !store.snapshot.bookmarks.isEmpty {
                    Text("ブックマーク").font(.headline)
                    ForEach(store.snapshot.bookmarks.prefix(8)) { bookmark in
                        Button { store.open(bookmark.url) } label: {
                            HStack {
                                Image(systemName: "bookmark")
                                VStack(alignment: .leading) {
                                    Text(bookmark.title).lineLimit(1)
                                    Text(bookmark.url.host ?? "").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Divider()
                    Button("ブックマークに追加", systemImage: "bookmark") { store.addBookmark() }
                        .disabled(tab.url.map { !WebURLPolicy.allows($0) } ?? true)
                    Button("ブックマーク", systemImage: "book") { showSheet(.bookmarks) }
                    Button("履歴", systemImage: "clock") { showSheet(.history) }
                    Button("共有", systemImage: "square.and.arrow.up", action: share)
                        .disabled(tab.url.map { !WebURLPolicy.allows($0) } ?? true)
                    Divider()
                    Button("設定", systemImage: "slider.horizontal.3") { showSheet(.settings) }
                } label: {
                    Image(systemName: "ellipsis.circle").frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("メニュー")
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

@MainActor
struct TabsView: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.tabs) { tab in
                    HStack {
                        Button {
                            store.select(tab)
                            dismiss()
                        } label: {
                            TabRow(tab: tab, selected: store.selectedID == tab.id)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        Button("タブを閉じる", systemImage: "xmark") { store.close(tab) }
                            .buttonStyle(.borderless).labelStyle(.iconOnly)
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { store.tabs[$0] }
                    for tab in removed { store.close(tab) }
                }
            }
            .navigationTitle("タブ \(store.tabs.count)")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("追加", systemImage: "plus") {
                        Button("通常タブ") { if store.newTab() != nil { dismiss() } }
                        Button("プライベートタブ") { if store.newTab(isPrivate: true) != nil { dismiss() } }
                    }
                    .accessibilityIdentifier("addTabMenu")
                }
            }
        }
    }
}

struct TabRow: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tab.isPrivate ? "hand.raised" : "globe")
                .foregroundStyle(tab.isPrivate ? .purple : .blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title).lineLimit(1)
                Text(tab.url?.host ?? (tab.isPrivate ? "プライベート" : "新しいタブ"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(.blue) }
        }
        .padding(.vertical, 6)
    }
}

@MainActor
struct LibraryView: View {
    @ObservedObject var store: BrowserStore
    let showHistory: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                if showHistory {
                    if store.snapshot.history.isEmpty { Text("履歴はありません").foregroundStyle(.secondary) }
                    ForEach(store.snapshot.history) { item in
                        pageButton(title: item.title, url: item.url)
                    }
                } else {
                    if store.snapshot.bookmarks.isEmpty { Text("ブックマークはありません").foregroundStyle(.secondary) }
                    ForEach(store.snapshot.bookmarks) { item in
                        pageButton(title: item.title, url: item.url)
                    }
                    .onDelete(perform: store.deleteBookmarks)
                }
            }
            .navigationTitle(showHistory ? "履歴" : "ブックマーク")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if showHistory {
                        Button("消去", role: .destructive) { confirmClear = true }
                            .disabled(store.snapshot.history.isEmpty)
                    } else { EditButton() }
                }
            }
            .confirmationDialog("閲覧履歴をすべて消去しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("履歴を消去", role: .destructive) { store.clearHistory() }
            }
        }
    }

    private func pageButton(title: String, url: URL) -> some View {
        Button {
            store.open(url)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(.primary).lineLimit(1)
                Text(url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
