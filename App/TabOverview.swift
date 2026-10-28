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
            TabGridView(store: store, tabs: filtered, columns: store.presentation.tabColumns, reduceMotion: reduceMotion) { tab in
                store.select(tab); dismiss()
            }
            .onAppear { store.overviewPresented = true; store.selectedTab?.capturePreview() }
            .onDisappear { store.overviewPresented = false }
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
                        if store.newTab(isPrivate: store.selectedTab?.isPrivate ?? false, atEnd: true) != nil { dismiss() }
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
