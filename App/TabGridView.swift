import SwiftUI
import UIKit
import ImageIO

/// Decoded previews are shared by cells and swipe overlays. Never decode JPEGs
/// on each gesture frame; the cache can evict them under memory pressure.
@MainActor
final class PreviewImages {
    static let shared = PreviewImages()
    private let images = NSCache<NSString, UIImage>()
    init() { images.totalCostLimit = 32 * 1024 * 1024 }
    func image(_ tab: BrowserTab) -> UIImage? {
        let key = (tab.id.uuidString + tab.previewGeneration.uuidString) as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let data = tab.previewData, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 720, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cg)
        images.setObject(image, forKey: key, cost: cg.bytesPerRow * cg.height)
        return image
    }
}

@MainActor
struct TabGridView: UIViewRepresentable {
    @ObservedObject var store: BrowserStore
    let tabs: [BrowserTab]
    let columns: Int
    let reduceMotion: Bool
    let select: (BrowserTab) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumLineSpacing = 16; layout.minimumInteritemSpacing = 16
        layout.sectionInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear; view.alwaysBounceVertical = true
        view.register(SwipeTabCell.self, forCellWithReuseIdentifier: "tab")
        context.coordinator.configure(view)
        return view
    }
    func updateUIView(_ view: UICollectionView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.update(view)
    }
    final class Coordinator: NSObject, UICollectionViewDelegateFlowLayout {
        var parent: TabGridView
        var source: UICollectionViewDiffableDataSource<Int, UUID>!
        private var initialScroll = false
        private var displayedColumns = 0
        private var displayedSelected: UUID?
        init(_ parent: TabGridView) { self.parent = parent }
        func configure(_ view: UICollectionView) {
            view.delegate = self
            source = UICollectionViewDiffableDataSource<Int, UUID>(collectionView: view) { [weak self] collection, index, id in
                guard let self, let tab = self.parent.tabs.first(where: { $0.id == id }),
                      let cell = collection.dequeueReusableCell(withReuseIdentifier: "tab", for: index) as? SwipeTabCell else { return nil }
                self.parent.store.loadPreview(tab)
                cell.resetSwipe()
                cell.onClose = { [weak self, weak tab] in
                    guard let self, let tab else { return }
                    // Update the collection now, while the finger is still down.
                    self.parent.store.close(tab)
                    self.parent.tabsUpdated(in: collection, coordinator: self)
                }
                cell.contentConfiguration = UIHostingConfiguration {
                    TabCard(tab: tab, selected: self.parent.store.selectedID == id,
                            select: { [weak self, weak tab] in if let self, let tab { self.parent.select(tab) } },
                            close: { [weak cell] in cell?.commitClose() })
                }.margins(.all, 0)
                return cell
            }
        }
        func update(_ view: UICollectionView) {
            if displayedColumns != parent.columns { displayedColumns = parent.columns; view.collectionViewLayout.invalidateLayout() }
            let ids = parent.tabs.map(\.id)
            guard source.snapshot().itemIdentifiers != ids || displayedSelected != parent.store.selectedID else { return }
            var snapshot = NSDiffableDataSourceSnapshot<Int, UUID>(); snapshot.appendSections([0]); snapshot.appendItems(ids)
            let oldIDs = Set(source.snapshot().itemIdentifiers)
            let selectedIDs = Set([displayedSelected, parent.store.selectedID].compactMap { $0 })
            snapshot.reconfigureItems(ids.filter { oldIDs.contains($0) && selectedIDs.contains($0) })
            displayedSelected = parent.store.selectedID
            let animate = initialScroll && !parent.reduceMotion
            UIView.animate(withDuration: animate ? 0.22 : 0, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.source.apply(snapshot, animatingDifferences: animate)
            } completion: { [weak self, weak view] _ in
                guard let self, let view, !self.initialScroll else { return }
                self.initialScroll = true
                view.layoutIfNeeded()
                if let id = self.parent.store.selectedID, let index = self.source.indexPath(for: id) {
                    view.scrollToItem(at: index, at: id == ids.last ? .bottom : .centeredVertically, animated: false)
                }
            }
        }
        func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = floor(max(1, collectionView.bounds.width - 32 - CGFloat(parent.columns - 1) * 16) / CGFloat(parent.columns))
            return CGSize(width: width, height: min(300, max(64, width * 0.95)) + 44)
        }
    }
    private func tabsUpdated(in view: UICollectionView, coordinator: Coordinator) {
        var updated = self
        let allowed = Set(store.tabs.map(\.id))
        updated = TabGridView(store: store, tabs: tabs.filter { allowed.contains($0.id) }, columns: columns, reduceMotion: reduceMotion, select: select)
        coordinator.parent = updated; coordinator.update(view)
    }
}

@MainActor
final class SwipeTabCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    var onClose: (() -> Void)?
    private var committed = false
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
    override init(frame: CGRect) {
        super.init(frame: frame); pan.delegate = self; contentView.addGestureRecognizer(pan)
        contentView.clipsToBounds = true; contentView.layer.cornerRadius = 14
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() { super.prepareForReuse(); onClose = nil; resetSwipe() }
    func resetSwipe() { committed = false; contentView.transform = .identity; contentView.alpha = 1 }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: self)
        return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.4
    }
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard !committed else { return }
        let x = min(0, gesture.translation(in: self).x)
        switch gesture.state {
        case .changed:
            contentView.transform = CGAffineTransform(translationX: x, y: 0)
            if x < -min(80, bounds.width * 0.38) { commitClose() }
        case .ended:
            if x < -25 && gesture.velocity(in: self).x < -650 { commitClose() }
            else { restorePosition() }
        case .cancelled, .failed: restorePosition()
        default: break
        }
    }
    private func restorePosition() {
        UIView.animate(withDuration: 0.18, delay: 0, options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) { self.contentView.transform = .identity }
    }
    func commitClose() {
        guard !committed else { return }; committed = true
        onClose?()
    }
}

@MainActor
struct TabCard: View {
    @ObservedObject var tab: BrowserTab
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: tab.isPrivate ? "hand.raised.fill" : "globe").foregroundStyle(tab.isPrivate ? .purple : .blue)
                    Text(tab.title).font(.caption.bold()).lineLimit(1)
                    Spacer(minLength: 0)
                    Button("タブを閉じる", systemImage: "xmark", action: close).labelStyle(.iconOnly)
                        .frame(width: 40, height: 44).accessibilityIdentifier("closeTab-" + tab.id.uuidString)
                }.padding(.leading, 8).frame(height: 44).background(.regularMaterial)
                Button(action: select) {
                    ZStack {
                        Color(uiColor: .secondarySystemBackground)
                        if let image = PreviewImages.shared.image(tab) {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: max(0, geometry.size.height - 44), alignment: .top).clipped()
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: tab.isPrivate ? "hand.raised" : "globe").font(.largeTitle)
                                Text(tab.url?.host ?? "新しいタブ").font(.caption).lineLimit(2)
                            }.foregroundStyle(.secondary).padding()
                        }
                        if tab.hasActiveMedia { Image(systemName: "play.circle.fill").font(.largeTitle).foregroundStyle(.white).shadow(radius: 3) }
                    }.frame(width: geometry.size.width, height: max(0, geometry.size.height - 44)).clipped().contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(tab.title + (selected ? "、選択中" : ""))
                    .accessibilityValue(tab.previewData == nil ? "プレビューなし" : "プレビューあり")
            }
            .background(.background).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3).allowsHitTesting(false))
            .accessibilityAction(named: Text("閉じる"), close)
        }
    }
}
