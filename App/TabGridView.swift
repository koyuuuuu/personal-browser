import SwiftUI
import UIKit
import ImageIO
import Combine

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
                cell.onClose = { [weak self, weak tab, weak collection] in
                    guard let self, let tab, let collection else { return }
                    // Update the collection now, while the finger is still down.
                    self.parent.store.close(tab)
                    self.parent.tabsUpdated(in: collection, coordinator: self)
                }
                cell.configure(tab: tab, selected: self.parent.store.selectedID == id, textSize: self.parent.store.presentation.interfaceTextSize) { [weak self, weak tab] in
                    if let self, let tab { self.parent.select(tab) }
                }
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
        let allowed = Set(store.tabs.map(\.id))
        let updated = TabGridView(store: store, tabs: tabs.filter { allowed.contains($0.id) }, columns: columns, reduceMotion: reduceMotion, select: select)
        coordinator.parent = updated; coordinator.update(view)
    }
}

@MainActor
final class SwipeTabCell: UICollectionViewCell, UIGestureRecognizerDelegate {
    var onClose: (() -> Void)?
    private var onSelect: (() -> Void)?
    private var committed = false
    private var observation: AnyCancellable?
    private weak var tab: BrowserTab?
    private var selectedTab = false
    private let header = UIView()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let previewButton = UIButton(type: .custom)
    private let previewImage = UIImageView()
    private let placeholder = UILabel()
    private let playing = UIImageView(image: UIImage(systemName: "play.circle.fill"))
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
    override init(frame: CGRect) {
        super.init(frame: frame)
        pan.delegate = self; pan.cancelsTouchesInView = true; addGestureRecognizer(pan)
        contentView.clipsToBounds = true; contentView.layer.cornerRadius = 14
        contentView.backgroundColor = .secondarySystemBackground
        header.backgroundColor = .tertiarySystemBackground
        contentView.addSubview(header); header.addSubview(icon); header.addSubview(titleLabel); header.addSubview(closeButton)
        titleLabel.font = .preferredFont(forTextStyle: .caption1); titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail
        icon.contentMode = .scaleAspectFit
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.accessibilityLabel = "タブを閉じる"
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        contentView.addSubview(previewButton)
        previewButton.clipsToBounds = true
        previewButton.addTarget(self, action: #selector(selectTapped), for: .touchUpInside)
        previewButton.addSubview(previewImage); previewButton.addSubview(placeholder); previewButton.addSubview(playing)
        previewImage.contentMode = .scaleToFill; previewImage.isUserInteractionEnabled = false
        placeholder.font = .preferredFont(forTextStyle: .caption1); placeholder.textAlignment = .center
        placeholder.numberOfLines = 2; placeholder.textColor = .secondaryLabel; placeholder.isUserInteractionEnabled = false
        playing.tintColor = .white; playing.contentMode = .scaleAspectFit; playing.isUserInteractionEnabled = false
        previewButton.isAccessibilityElement = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func prepareForReuse() {
        super.prepareForReuse(); observation = nil; tab = nil; onClose = nil; onSelect = nil; resetSwipe()
    }
    func configure(tab: BrowserTab, selected: Bool, textSize: InterfaceTextSize, select: @escaping () -> Void) {
        observation = nil; self.tab = tab; selectedTab = selected; onSelect = select
        let category: UIContentSizeCategory? = switch textSize {
        case .system: nil
        case .small: .small
        case .standard: .large
        case .large: .extraLarge
        case .extraLarge: .extraExtraLarge
        }
        let traits = category.map { UITraitCollection(preferredContentSizeCategory: $0) }
        titleLabel.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        placeholder.font = .preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        refresh()
        observation = tab.objectWillChange.sink { [weak self] in
            // @Published announces before changing the value.
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }
    private func refresh() {
        guard let tab else { return }
        titleLabel.text = tab.title
        icon.image = UIImage(systemName: tab.isPrivate ? "hand.raised.fill" : "globe")
        icon.tintColor = tab.isPrivate ? .systemPurple : .systemBlue
        closeButton.accessibilityIdentifier = "closeTab-" + tab.id.uuidString
        previewImage.image = PreviewImages.shared.image(tab)
        placeholder.isHidden = previewImage.image != nil
        placeholder.text = tab.url?.host ?? "新しいタブ"
        playing.isHidden = !tab.hasActiveMedia
        previewButton.accessibilityLabel = tab.title + (selectedTab ? "、選択中" : "")
        previewButton.accessibilityValue = tab.previewData == nil ? "プレビューなし" : "プレビューあり"
        contentView.layer.borderWidth = selectedTab ? 3 : 0
        contentView.layer.borderColor = (tab.isPrivate ? UIColor.systemPurple : .systemBlue).cgColor
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        let width = contentView.bounds.width
        header.frame = CGRect(x: 0, y: 0, width: width, height: 44)
        icon.frame = CGRect(x: 8, y: 13, width: 18, height: 18)
        closeButton.frame = CGRect(x: width - 40, y: 0, width: 40, height: 44)
        titleLabel.frame = CGRect(x: 32, y: 0, width: max(0, width - 72), height: 44)
        previewButton.frame = CGRect(x: 0, y: 44, width: width, height: max(0, contentView.bounds.height - 44))
        let box = previewButton.bounds
        if let image = previewImage.image {
            let scale = max(box.width / image.size.width, box.height / image.size.height)
            previewImage.frame = CGRect(x: (box.width - image.size.width * scale) / 2, y: 0, width: image.size.width * scale, height: image.size.height * scale)
        } else { previewImage.frame = box }
        placeholder.frame = box.insetBy(dx: 10, dy: 10)
        playing.frame = CGRect(x: box.midX - 18, y: box.midY - 18, width: 36, height: 36)
    }
    func resetSwipe() { committed = false; contentView.transform = .identity; contentView.alpha = 1 }
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return super.gestureRecognizerShouldBegin(gestureRecognizer) }
        let velocity = pan.velocity(in: self)
        return velocity.x < 0 && abs(velocity.x) > abs(velocity.y) * 1.4
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Vertical collection scrolling remains available; our horizontal test
        // rejects those gestures before moving a cell.
        gestureRecognizer === pan && otherGestureRecognizer is UIPanGestureRecognizer
    }
    @objc private func selectTapped() { guard !committed, pan.state != .began, pan.state != .changed else { return }; onSelect?() }
    @objc private func closeTapped() { commitClose() }
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
