import SwiftUI
import WebKit
import MessageUI

struct ShareRequest: Identifiable {
    let id = UUID()
    let url: URL
}

enum BrowserSheet: Identifiable {
    case tabs, bookmarks, history, settings, downloads
    case connection(ConnectionRequest)
    case share(ShareRequest), message(ShareRequest), safari(ShareRequest)
    var id: String {
        switch self {
        case .connection(let request): "connection-" + request.id.uuidString
        case .tabs: "tabs"; case .bookmarks: "bookmarks"; case .history: "history"
        case .settings: "settings"; case .downloads: "downloads"; case .share(let payload): "share-" + payload.id.uuidString
        case .message(let payload): "message-" + payload.id.uuidString
        case .safari(let payload): "safari-" + payload.id.uuidString
        }
    }
}

@MainActor
struct BrowserRootView: View {
    @EnvironmentObject private var updates: UpdateChecker
    @ObservedObject var store: BrowserStore
    @State private var sheet: BrowserSheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var linkDocument = LinkFileDocument()
    @State private var exportLink = false
    @Environment(\.dynamicTypeSize) private var systemTextSize

    var body: some View {
        connectedContent
        .fileExporter(isPresented: $exportLink, document: linkDocument, contentType: LinkFileDocument.contentType, defaultFilename: "Webリンク") { result in
            if case .failure = result { store.notice = "リンクを保存できませんでした。" }
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeBrowserLibrary)) { _ in sheet = nil }
        .onChange(of: store.shareRequest?.id) { _, _ in
            if let payload = store.shareRequest { sheet = .share(payload) }
        }
        .persistentSystemOverlays(store.presentation.hideHomeIndicator ? .hidden : .automatic)
        .environment(\.dynamicTypeSize, store.presentation.interfaceTextSize.dynamicSize ?? systemTextSize)
        .statusBarHidden(store.landscape)
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
            Button("開く") { UIApplication.shared.open(url); store.externalURL = nil }
            Button("キャンセル", role: .cancel) { store.externalURL = nil }
        } message: { url in Text(url.absoluteString) }
    }

    private var connectedContent: some View {
        browsingContent
        .safeAreaInset(edge: .top, spacing: 0) { updateBanner }
        .tint(store.selectedTab?.isPrivate == true ? .purple : .blue)
        .sheet(item: $sheet) { route in
            sheetContent(route)
                .persistentSystemOverlays(store.presentation.hideHomeIndicator ? .hidden : .automatic)
                .environment(\.dynamicTypeSize, store.presentation.interfaceTextSize.dynamicSize ?? systemTextSize)
        }
        .onChange(of: store.connectionRequest?.id) { _, _ in
            if let request = store.connectionRequest { sheet = .connection(request) }
        }
        .onChange(of: store.safariRequest?.id) { _, _ in
            if let payload = store.safariRequest { sheet = .safari(payload) }
        }
        .onChange(of: store.messageRequest?.id) { _, _ in
            if let payload = store.messageRequest {
                if MFMessageComposeViewController.canSendText() { sheet = .message(payload) }
                else { store.notice = "メッセージを送信できません。端末のメッセージ設定を確認してください。" }
            }
        }
        .onChange(of: store.saveLinkRequest?.id) { _, _ in
            if let payload = store.saveLinkRequest { linkDocument = LinkFileDocument(url: payload.url); exportLink = true }
        }
    }

    @ViewBuilder private var browsingContent: some View {
        if let tab = store.selectedTab {
            TabBrowserView(store: store, tab: tab, showSheet: { sheet = $0 }, share: share)
        } else { ProgressView("Webサイトデータを消去中…") }
    }
    @ViewBuilder private var updateBanner: some View {
        if updates.shouldPresent, let update = updates.available {
            HStack {
                Text("新しいバージョン \(update.displayVersion)").font(.callout)
                Spacer()
                Button("SideStore") { updates.openSideStore() }
                Button("閉じる", systemImage: "xmark") { updates.dismissedVersion = update.displayVersion }.labelStyle(.iconOnly)
            }.padding(10).background(.thinMaterial)
        }
    }
    @ViewBuilder private func sheetContent(_ route: BrowserSheet) -> some View {
        switch route {
        case .connection(let request): ConnectionPrompt(request: request)
        case .tabs: TabsView(store: store)
        case .bookmarks: LibraryView(store: store, showHistory: false)
        case .history: LibraryView(store: store, showHistory: true)
        case .settings: SettingsView(store: store)
        case .downloads: DownloadsView(store: store)
        case .share(let payload): ActivityView(items: [payload.url])
        case .message(let payload): MessageComposer(url: payload.url)
        case .safari(let payload): SafariScreen(url: payload.url)
        }
    }

    private func share() {
        guard let url = store.selectedTab?.url, WebURLPolicy.allows(url) else { return }
        sheet = .share(ShareRequest(url: url))
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
