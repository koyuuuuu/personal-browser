import SwiftUI
import WebKit

@MainActor
struct TabBrowserView: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let showSheet: (BrowserSheet) -> Void
    let share: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var address = ""
    @State private var promptText = ""
    @State private var transitionProgress = 1.0
    @FocusState private var addressFocused: Bool

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height && geometry.size.width > 550
            VStack(spacing: 0) {
                if store.chromeVisible && (landscape || store.snapshot.settings.toolbarPosition == .top) { chrome(compact: landscape, width: geometry.size.width) }
                if tab.isPrivate && !landscape && store.chromeVisible {
                    Label("プライベート · 履歴とタブを端末に保存しません", systemImage: "hand.raised")
                        .font(.caption).foregroundStyle(.purple).padding(6).frame(maxWidth: .infinity)
                }
                if let error = tab.errorMessage, store.chromeVisible {
                    HStack {
                        Text(error).font(.caption).lineLimit(landscape ? 1 : 3)
                        Spacer()
                        Button("閉じる", systemImage: "xmark") { tab.errorMessage = nil }.labelStyle(.iconOnly)
                    }.padding(8).background(Color.orange.opacity(0.12))
                }
                viewport(width: geometry.size.width)
                if !landscape && store.chromeVisible && store.snapshot.settings.toolbarPosition == .bottom { chrome(compact: false, width: geometry.size.width) }
            }
            .overlay(alignment: landscape || store.snapshot.settings.toolbarPosition == .top ? .top : .bottom) {
                if !store.chromeVisible {
                    Button { store.revealChrome() } label: {
                        Image(systemName: landscape || store.snapshot.settings.toolbarPosition == .top ? "chevron.down" : "chevron.up")
                            .font(.system(size: 12, weight: .semibold)).frame(width: 44, height: 24)
                            .background(.regularMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain).accessibilityLabel("バーを表示")
                    .accessibilityIdentifier("showChromeButton").padding(2)
                }
            }
            .onAppear { store.setLandscape(landscape) }
            .onChange(of: landscape) { _, value in addressFocused = false; store.setLandscape(value) }
        }
        .background(Color(uiColor: .systemBackground))
        .ignoresSafeArea(.container, edges: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.chromeVisible)
        .onAppear { address = tab.url?.absoluteString ?? "" }
        .onChange(of: tab.id) { _, _ in address = tab.url?.absoluteString ?? ""; addressFocused = false }
        .onChange(of: tab.url) { _, url in if !addressFocused { address = url?.absoluteString ?? "" } }
        .onChange(of: addressFocused) { _, focused in if !focused { address = tab.url?.absoluteString ?? "" } }
        .onChange(of: tab.dialog?.id) { _, _ in promptText = tab.dialog?.defaultText ?? "" }
        .task(id: store.tabTransition?.id) {
            guard store.tabTransition != nil, store.features.animateNewTabs, !reduceMotion else { transitionProgress = 1; return }
            transitionProgress = 0
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.24)) { transitionProgress = 1 }
        }
        .onDisappear { tab.dialog?.resolve(nil); tab.dialog = nil }
        .alert("Webページからのメッセージ", isPresented: Binding(get: { tab.dialog != nil }, set: { if !$0 { finishDialog(nil) } }), presenting: tab.dialog) { dialog in
            if dialog.kind == .prompt { TextField("入力", text: $promptText) }
            Button("OK") { finishDialog(dialog.kind == .prompt ? promptText : "OK") }
            if dialog.kind != .alert { Button("キャンセル", role: .cancel) { finishDialog(nil) } }
        } message: { dialog in Text(dialog.message) }
    }

    private func viewport(width: CGFloat) -> some View {
        let direction = CGFloat(store.tabTransition?.direction ?? 1)
        return ZStack {
            ZStack {
                // This identity never changes when selecting a different tab.
                WebSurface(store: store).accessibilityIdentifier("webContent").accessibilityHidden(!tab.hasContent)
                if !tab.hasContent {
                    HomePageView(store: store, isPrivate: tab.isPrivate)
                        .id(tab.id)
                        .simultaneousGesture(DragGesture(minimumDistance: 18).onEnded { value in
                            if abs(value.translation.height) > abs(value.translation.width) {
                                store.scrollChrome(delta: -Double(value.translation.height))
                            }
                        })
                }
            }
            .offset(x: (1 - transitionProgress) * direction * width * 0.15)
            if transitionProgress < 1 {
                GeometryReader { geometry in
                    Group {
                        if let data = store.tabTransition?.outgoingImage, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else { Color(uiColor: .secondarySystemBackground) }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                .offset(x: -transitionProgress * direction * width)
                .opacity(1 - transitionProgress).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
    }
    private func chrome(compact: Bool, width: CGFloat) -> some View {
        BrowserChrome(store: store, tab: tab, compact: compact, availableWidth: width, address: $address, addressFocused: $addressFocused, showSheet: showSheet, share: share)
    }
    private func finishDialog(_ value: String?) { let dialog = tab.dialog; tab.dialog = nil; dialog?.resolve(value) }
}

@MainActor
struct BrowserChrome: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var tab: BrowserTab
    let compact: Bool
    let availableWidth: CGFloat
    @ScaledMetric(relativeTo: .body) private var addressFont = 16.0
    @Binding var address: String
    var addressFocused: FocusState<Bool>.Binding
    let showSheet: (BrowserSheet) -> Void
    let share: () -> Void
    private var actions: [BrowserAction] { store.snapshot.settings.actions }
    private var middle: Int { (actions.count + 1) / 2 }
    private var leftActions: [BrowserAction] {
        store.presentation.customAddressButtons ? store.presentation.addressLeft : (compact ? Array(actions.prefix(middle)) : [])
    }
    private var rightActions: [BrowserAction] {
        store.presentation.customAddressButtons ? store.presentation.addressRight : (compact ? Array(actions.dropFirst(middle)) : [])
    }
    private func sideWidth(_ values: [BrowserAction]) -> CGFloat {
        let total = leftActions.count + rightActions.count
        guard total > 0 else { return 0 }
        let budget = max(0, availableWidth - (compact ? 96 : 58) - (compact ? 196 : 130))
        return min(CGFloat(values.count) * 32, budget * CGFloat(values.count) / CGFloat(total))
    }
    private func sideButtons(_ values: [BrowserAction], left: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(values) { action in
                    Button { perform(action) } label: { Image(systemName: action == .reload && tab.isLoading ? "xmark" : action.symbol).font(.system(size: 17)).frame(width: 32, height: 36) }
                        .accessibilityLabel(action.label).accessibilityIdentifier((left ? "addressLeft-" : "addressRight-") + action.rawValue).disabled(disabled(action))
                }
            }
        }.frame(width: sideWidth(values), height: 36)
    }
    var body: some View {
        Group {
            if compact {
                HStack(spacing: 4) {
                    if !leftActions.isEmpty { sideButtons(leftActions, left: true) }
                    addressEntry.layoutPriority(1)
                    if !rightActions.isEmpty { sideButtons(rightActions, left: false) }
                    menu
                    hideButton
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .overlay(alignment: .bottom) { if tab.isLoading { ProgressView(value: tab.progress).frame(height: 2).clipped() } }
            } else {
                VStack(spacing: 2) {
                    if tab.isLoading { ProgressView(value: tab.progress).frame(height: 2) }
                    HStack(spacing: 4) {
                        if !leftActions.isEmpty { sideButtons(leftActions, left: true) }
                        addressEntry.layoutPriority(1)
                        if !rightActions.isEmpty { sideButtons(rightActions, left: false) }
                        hideButton
                    }.padding(.horizontal, 8)
                    HStack(spacing: 0) {
                        ForEach(actions) { action in actionButton(action) }
                        menu
                    }.padding(.horizontal, 4)
                }.padding(.top, 4).padding(.bottom, 4)
            }
        }
        .background(.regularMaterial)
        .accessibilityIdentifier(compact ? "landscapeChrome" : "portraitChrome")
    }
    private var addressEntry: some View {
        HStack(spacing: 6) {
            Image(systemName: tab.url?.scheme == "http" ? "exclamationmark.circle" : "globe").font(.system(size: compact ? 12 : 15)).foregroundStyle(.secondary)
            TextField("URLまたは検索語", text: $address)
                .font(.system(size: compact ? addressFont * 0.875 : addressFont)).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.webSearch).submitLabel(.go)
                .focused(addressFocused).accessibilityIdentifier("addressField")
                .onSubmit { let input = address; addressFocused.wrappedValue = false; store.navigate(input) }
            if addressFocused.wrappedValue {
                Button("入力を消去", systemImage: "xmark.circle.fill") { address = "" }.labelStyle(.iconOnly).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: compact ? 180 : 110, minHeight: compact ? 28 : 34)
        .contentShape(Rectangle())
        .highPriorityGesture(DragGesture(minimumDistance: 35).onEnded { value in
            guard store.features.swipeAddressToSwitchTabs, !addressFocused.wrappedValue,
                  abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            store.switchTab(towardNext: value.translation.width < 0)
        }, including: store.features.swipeAddressToSwitchTabs && !addressFocused.wrappedValue ? .all : .subviews)
        .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 2 : 3)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: compact ? 8 : 12))
    }
    private var hideButton: some View {
        Button { addressFocused.wrappedValue = false; store.hideChrome() } label: {
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 15)).frame(width: 30, height: compact ? 36 : 38)
        }
        .accessibilityLabel("バーを非表示").accessibilityIdentifier("hideChromeButton")
    }
    private func actionButton(_ action: BrowserAction) -> some View {
        Button { perform(action) } label: {
            Image(systemName: action == .reload && tab.isLoading ? "xmark" : action.symbol)
                .font(.system(size: compact ? 17 : 20))
                .frame(maxWidth: compact ? 32 : .infinity, minHeight: compact ? 36 : 40)
        }
        .accessibilityLabel(action == .reload && tab.isLoading ? "読み込みを停止" : action.label)
        .accessibilityIdentifier(action.rawValue + "Button").disabled(disabled(action))
    }
    private var menu: some View {
        Menu {
            Button("新しいタブ", systemImage: "plus") { _ = store.newTab(isPrivate: tab.isPrivate) }
            Button("新しいプライベートタブ", systemImage: "hand.raised") { _ = store.newTab(isPrivate: true) }
            Button("タブ一覧", systemImage: "square.on.square") { showSheet(.tabs) }
            Button("閉じたタブを戻す", systemImage: "arrow.uturn.backward") { store.restoreClosedTab() }.disabled(store.closedTabs.isEmpty)
            Button("ホーム", systemImage: "house") { store.showHome() }
            Divider()
            Button("お気に入りに追加", systemImage: "star") { store.addFavorite() }.disabled(disabled(.share))
            Button("ブックマークに追加", systemImage: "bookmark") { store.addBookmark() }.disabled(disabled(.share))
            Button("ブックマーク", systemImage: "book") { showSheet(.bookmarks) }
            Button("履歴", systemImage: "clock") { showSheet(.history) }
            Button("共有", systemImage: "square.and.arrow.up", action: share).disabled(disabled(.share))
            Button("ページ内を検索", systemImage: "magnifyingglass") { tab.webView.findInteraction?.presentFindNavigator(showingReplace: false) }.disabled(!tab.hasContent)
            Button("コピーしたリンクをWatch HTMLで解析", systemImage: "play.rectangle.on.rectangle") { store.analyzeCopiedLink() }
            if tab.url.map({ ["/watch", "/watch.html"].contains($0.path.lowercased()) }) == true {
                Button("このページをWatch HTMLの接続先にする", systemImage: "link.badge.plus") { store.useCurrentWatchHTML() }
            }
            Button("ダウンロード", systemImage: "arrow.down.circle") { showSheet(.downloads) }
            Divider()
            Button("設定", systemImage: "slider.horizontal.3") { showSheet(.settings) }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: compact ? 18 : 20))
                .frame(maxWidth: compact ? 32 : .infinity, minHeight: compact ? 36 : 40).contentShape(Rectangle())
        }
        .accessibilityLabel("メニュー").accessibilityIdentifier("menuButton")
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
        addressFocused.wrappedValue = false
        switch action {
        case .back: tab.webView.goBack()
        case .forward: tab.webView.goForward()
        case .reload:
            if tab.isLoading { tab.webView.stopLoading() }
            else if tab.webView.url != nil { tab.webView.reload() }
            else if let url = tab.url { tab.load(url) }
        case .newTab: _ = store.newTab(isPrivate: tab.isPrivate)
        case .tabs: showSheet(.tabs)
        case .bookmarks: showSheet(.bookmarks)
        case .share: share()
        }
    }
}
