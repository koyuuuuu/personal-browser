import SwiftUI

@MainActor
struct TabsView: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmClose = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var filtered: [BrowserTab] { store.tabs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false) } }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
              ScrollViewReader { proxy in
                let columns = store.presentation.tabColumns
                let width = (geometry.size.width - 32 - CGFloat(columns - 1) * 16) / CGFloat(columns)
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: columns), spacing: 16) {
                        ForEach(filtered) { tab in
                            TabTile(tab: tab, previewHeight: min(300, max(64, width * 0.95)), selected: store.selectedID == tab.id, select: {
                                guard store.tabs.contains(where: { $0.id == tab.id }) else { return }
                                store.select(tab); dismiss()
                            }, close: { store.close(tab) })
                            .id(tab.id)
                            .onAppear { store.loadPreview(tab) }
                            .transition(.opacity.combined(with: .scale(scale: 0.94)))
                        }
                    }
                    .padding()
                    .animation(reduceMotion ? nil : .snappy(duration: 0.24), value: filtered.map(\.id))
                }
                .task {
                    store.selectedTab?.capturePreview()
                    await Task.yield()
                    if let id = store.selectedID { proxy.scrollTo(id, anchor: filtered.last?.id == id ? .bottom : .center) }
                }
            }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .searchable(text: $query, prompt: "タブを検索")
            .navigationTitle("タブ \(store.tabs.count)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } } }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Menu("タブ操作", systemImage: "ellipsis.circle") {
                        Button("閉じたタブを戻す", systemImage: "arrow.uturn.backward") { store.restoreClosedTab(); dismiss() }.disabled(store.closedTabs.isEmpty)
                        Button("新しい通常タブ") { if store.newTab() != nil { dismiss() } }
                        Button("新しいプライベートタブ") { if store.newTab(isPrivate: true) != nil { dismiss() } }
                        Button("すべてのタブを閉じる", role: .destructive) { confirmClose = true }
                    }.labelStyle(.iconOnly).accessibilityIdentifier("addTabMenu").frame(width: 60, height: 44)
                    Spacer()
                    Button {
                        if store.newTab(isPrivate: store.selectedTab?.isPrivate ?? false) != nil { dismiss() }
                    } label: { Image(systemName: "plus").font(.system(size: 23)).frame(width: 60, height: 44) }
                    .accessibilityLabel("新しいタブ").accessibilityIdentifier("overviewNewTabButton")
                    Spacer()
                    Button("完了") { dismiss() }.frame(width: 60, height: 44)
                }
                .padding(.horizontal, 12).background(.regularMaterial)
            }
            .confirmationDialog("すべてのタブを閉じますか？", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("すべて閉じる", role: .destructive) { for tab in store.tabs { store.close(tab) } }
            }
        }
        .persistentSystemOverlays(store.presentation.hideHomeIndicator ? .hidden : .automatic)
    }
}

@MainActor
struct TabTile: View {
    @ObservedObject var tab: BrowserTab
    var previewHeight: CGFloat = 170
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var translation: CGFloat = 0
    @State private var closing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: tab.isPrivate ? "hand.raised.fill" : "globe").foregroundStyle(tab.isPrivate ? .purple : .blue)
                Text(tab.title).font(.caption.bold()).lineLimit(1)
                Spacer(minLength: 0)
                Button("タブを閉じる", systemImage: "xmark", action: animateClose).labelStyle(.iconOnly)
                    .padding(8).accessibilityIdentifier("closeTab-" + tab.id.uuidString)
            }.padding(.leading, 8).background(.regularMaterial)
            Button {
                guard !closing, abs(translation) < 8 else { return }
                select()
            } label: {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    if let data = tab.previewData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: previewHeight, alignment: .top).clipped()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: tab.isPrivate ? "hand.raised" : "globe").font(.largeTitle)
                            Text(tab.url?.host ?? "新しいタブ").font(.caption).lineLimit(2)
                        }.foregroundStyle(.secondary).padding()
                    }
                    if tab.hasActiveMedia { Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white).shadow(radius: 3) }
                }.frame(height: previewHeight).clipped().contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(tab.title + (selected ? "、選択中" : ""))
                .accessibilityValue(tab.previewData == nil ? "プレビューなし" : "プレビューあり")
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
        .offset(x: translation).opacity(closing ? 0 : max(0.5, 1 + translation / 500))
        .scaleEffect(closing ? 0.94 : 1)
        .simultaneousGesture(DragGesture(minimumDistance: 25).onChanged { value in
            guard !closing else { return }
            if value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) * 1.5 { translation = value.translation.width }
        }.onEnded { value in
            if (value.translation.width < -min(72, max(32, previewHeight * 0.42)) || value.predictedEndTranslation.width < -150) && abs(value.translation.width) > abs(value.translation.height) * 1.5 { animateClose() }
            else { withAnimation(.snappy) { translation = 0 } }
        })
        .accessibilityAction(named: Text("閉じる"), animateClose)
    }
    private func animateClose() {
        guard !closing else { return }
        if reduceMotion { closing = true; close(); return }
        withAnimation(.easeOut(duration: 0.18)) { closing = true; translation = -400 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.snappy(duration: 0.24)) { close() }
        }
    }
}
