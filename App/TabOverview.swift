import SwiftUI

@MainActor
struct TabsView: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmClose = false
    private var filtered: [BrowserTab] { store.tabs.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.url?.absoluteString.localizedCaseInsensitiveContains(query) ?? false) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(filtered) { tab in
                        TabTile(tab: tab, selected: store.selectedID == tab.id, select: { store.select(tab); dismiss() }, close: { store.close(tab) })
                    }
                }.padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .searchable(text: $query, prompt: "タブを検索")
            .navigationTitle("タブ \(store.tabs.count)")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("追加", systemImage: "plus") {
                        Button("通常タブ") { if store.newTab() != nil { dismiss() } }
                        Button("プライベートタブ") { if store.newTab(isPrivate: true) != nil { dismiss() } }
                        Button("すべてのタブを閉じる", role: .destructive) { confirmClose = true }
                    }.accessibilityIdentifier("addTabMenu")
                }
            }
            .onAppear { store.selectedTab?.capturePreview() }
            .confirmationDialog("すべてのタブを閉じますか？", isPresented: $confirmClose, titleVisibility: .visible) {
                Button("すべて閉じる", role: .destructive) { for tab in store.tabs { store.close(tab) } }
            }
        }
    }
}

@MainActor
struct TabTile: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var translation: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: tab.isPrivate ? "hand.raised.fill" : "globe").foregroundStyle(tab.isPrivate ? .purple : .blue)
                Text(tab.title).font(.caption.bold()).lineLimit(1)
                Spacer(minLength: 0)
                Button("タブを閉じる", systemImage: "xmark", action: close).labelStyle(.iconOnly)
                    .padding(8).accessibilityIdentifier("closeTab-" + tab.id.uuidString)
            }.padding(.leading, 8).background(.regularMaterial)
            Button(action: select) {
                ZStack {
                    Color(uiColor: .secondarySystemBackground)
                    if let data = tab.previewData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 170, alignment: .top).clipped()
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: tab.isPrivate ? "hand.raised" : "globe").font(.largeTitle)
                            Text(tab.url?.host ?? "新しいタブ").font(.caption).lineLimit(2)
                        }.foregroundStyle(.secondary).padding()
                    }
                    if tab.hasActiveMedia { Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white).shadow(radius: 3) }
                }.frame(height: 170).clipped().contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(tab.title + (selected ? "、選択中" : ""))
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 3))
        .accessibilityIdentifier("tabTile-" + tab.id.uuidString)
        .offset(x: translation).opacity(translation < -40 ? 0.55 : 1)
        .simultaneousGesture(DragGesture(minimumDistance: 25).onChanged { value in
            if value.translation.width < 0 && abs(value.translation.width) > abs(value.translation.height) * 1.5 { translation = value.translation.width }
        }.onEnded { value in
            if value.translation.width < -80 && abs(value.translation.width) > abs(value.translation.height) * 1.5 { close() }
            else { withAnimation(.snappy) { translation = 0 } }
        })
        .accessibilityAction(named: Text("閉じる"), close)
    }
}
