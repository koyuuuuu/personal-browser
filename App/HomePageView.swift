import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct HomePageView: View {
    @ObservedObject var store: BrowserStore
    let isPrivate: Bool
    @State private var editing: Bookmark?
    @State private var draggingFavorite: UUID?
    @State private var lastDragTarget: UUID?
    var body: some View {
        GeometryReader { geometry in
            let columns = store.features.favoriteColumns
            let iconSize = min(50, max(28, (geometry.size.width - 40 - CGFloat(columns - 1) * 12) / CGFloat(columns) - 12))
            ZStack {
                if store.features.showHomeBackground, store.homeBackground != nil {
                    HomeBackgroundImage(store: store)
                    Rectangle().fill(.black.opacity(0.2))
                } else { Color(uiColor: .systemBackground) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        Label(isPrivate ? "プライベートブラウズ" : "お気に入り", systemImage: isPrivate ? "hand.raised" : "star.fill")
                            .font(.title2.bold()).padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        if store.extras.favorites.isEmpty {
                            ContentUnavailableView("お気に入りを追加", systemImage: "star", description: Text("ページのメニューから「お気に入りに追加」を選ぶと、ここに並びます。ブックマークは本のボタンから開けます。"))
                                .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: store.features.favoriteColumns), spacing: 20) {
                            ForEach(store.extras.favorites) { item in
                                Button { store.open(item.url) } label: {
                                    VStack(spacing: 6) {
                                        SiteIcon(url: item.url, size: iconSize, allowNetwork: !isPrivate)
                                        Text(item.title).font(.caption2).lineLimit(2).multilineTextAlignment(.center)
                                            .frame(height: 30).frame(maxWidth: .infinity)
                                    }
                                    .padding(6).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("favorite-" + item.id.uuidString)
                                .onDrag {
                                    draggingFavorite = item.id; lastDragTarget = nil
                                    return NSItemProvider(object: item.id.uuidString as NSString)
                                }
                                .onDrop(of: [UTType.text], delegate: FavoriteDropDelegate(
                                    target: item.id, dragging: $draggingFavorite, lastTarget: $lastDragTarget, store: store))
                                .contextMenu {
                                    Button("新しいタブで開く", systemImage: "plus.square") { _ = store.newTab(isPrivate: isPrivate, url: item.url) }
                                    Button("編集", systemImage: "pencil") { editing = item }
                                    Button("前へ移動", systemImage: "arrow.left") { store.moveFavorite(item.id, by: -1) }
                                    Button("後ろへ移動", systemImage: "arrow.right") { store.moveFavorite(item.id, by: 1) }
                                    Button("削除", systemImage: "trash", role: .destructive) { store.deleteFavorite(item.id) }
                                }
                            }
                        }
                        Text("URLや検索語をアドレス欄に入力してください。")
                            .font(.footnote).padding(10).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(20)
                }.contentShape(Rectangle()).clipped()
            }.frame(width: geometry.size.width, height: geometry.size.height).contentShape(Rectangle()).clipped()
        }
        .sheet(item: $editing) { item in BookmarkEditor(item: item, save: store.updateFavorite) }
    }
}

struct SiteIcon: View {
    let url: URL
    var size: CGFloat = 42
    var allowNetwork = true
    @AppStorage("site-icons.enabled") private var enabled = true
    @State private var image: UIImage?
    private var hue: Double { Double((url.host ?? "").utf8.reduce(0) { ($0 + Int($1)) % 360 }) / 360 }
    var body: some View {
        ZStack {
            if let image, enabled {
                Image(uiImage: image).resizable().scaledToFit().padding(size * 0.08)
                    .background(Color(uiColor: .secondarySystemBackground))
            } else {
                Color(hue: hue, saturation: 0.55, brightness: 0.7)
                Text(String((url.host?.replacingOccurrences(of: "www.", with: "") ?? "W").prefix(1)).uppercased())
                    .font(.system(size: size * 0.48, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23))
        .accessibilityHidden(true)
        .task(id: url.absoluteString + String(enabled)) {
            image = enabled ? await SiteIconLoader.shared.image(for: url, network: allowNetwork) : nil
        }
    }
}

@MainActor
private struct FavoriteDropDelegate: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    @Binding var lastTarget: UUID?
    let store: BrowserStore
    func validateDrop(info: DropInfo) -> Bool { dragging != nil }
    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target, lastTarget != target else { return }
        lastTarget = target
        withAnimation(.snappy(duration: 0.2)) { store.moveFavorite(dragging, onto: target) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        guard dragging != nil else { return false }
        dragging = nil; lastTarget = nil; return true
    }
}
