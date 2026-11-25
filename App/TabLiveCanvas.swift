import UIKit
import WebKit
import Combine

/// The document viewport stays fixed during a transition. Only its clipping
/// container moves/scales; retained WebViews never leave their window.
@MainActor
final class WebSurfaceView: UIView {
    let chromeRecovery = ChromeRecoveryObserver()
    private weak var store: BrowserStore?
    private var items: [UUID: LiveTabCanvasItem] = [:]
    private let outline = TabSelectionOutlineView()
    private var animating = false
    private var foregroundObservation: AnyCancellable?
    #if DEBUG
    private var motionProbe: OverviewMotionProbe?
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true; isOpaque = false; backgroundColor = .clear
        chromeRecovery.install(on: self)
        outline.isUserInteractionEnabled = false; outline.accessibilityElementsHidden = true
        outline.alpha = 0; addSubview(outline)
        foregroundObservation = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.setNeedsLayout() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func synchronize(_ store: BrowserStore) {
        self.store = store
        TabOverviewPresentation.shared.surface = self
        if !store.overviewPresented, let selected = store.selectedTab, selected.hasContent { _ = selected.webView }
        let openIDs = Set(store.tabs.map(\.id))
        for (id, item) in items where !openIDs.contains(id) || (!item.homeSnapshot && store.tabs.first(where: { $0.id == id })?.existingWebView == nil) {
            item.removeFromSuperview(); items.removeValue(forKey: id)
        }
        for tab in store.tabs {
            guard let webView = tab.existingWebView else { continue }
            if items[tab.id]?.content !== webView {
                items.removeValue(forKey: tab.id)?.removeFromSuperview()
                let item = LiveTabCanvasItem(content: webView, homeSnapshot: false)
                items[tab.id] = item; addSubview(item); item.setViewport(bounds.size)
            }
            items[tab.id]?.updatePictureInPicture(tab.isPictureInPicture)
            let interactive = !store.overviewPresented && tab.id == store.selectedID && tab.hasContent
            let hidden = store.overviewPresented || tab.id != store.selectedID
            if webView.isUserInteractionEnabled != interactive { webView.isUserInteractionEnabled = interactive }
            if webView.accessibilityElementsHidden != hidden { webView.accessibilityElementsHidden = hidden }
        }
        if !animating {
            if !store.overviewPresented { showBrowser() }
            else { TabOverviewPresentation.shared.synchronize() }
        }
        raiseSelectedAndOutline()
        chromeRecovery.webView = store.overviewPresented ? nil : store.selectedTab?.existingWebView
        chromeRecovery.hidden = { [weak store] in store?.chromeVisible == false }
        chromeRecovery.locked = { [weak store] in store?.selectedTab?.documentScrollLocked == true }
        chromeRecovery.reveal = { [weak store] in store?.revealChrome() }
        chromeRecovery.updateEnabled()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !animating, let store else { return }
        if !store.overviewPresented { showBrowser() }
        else { TabOverviewPresentation.shared.synchronize() }
    }
    private func raiseSelectedAndOutline() {
        if let selected = store?.selectedID, let item = items[selected], item.superview === self {
            // Keep all nonselected cards below this one, and the stroke above it.
            if subviews.dropLast().last !== item { bringSubviewToFront(item) }
        }
        if subviews.last !== outline { bringSubviewToFront(outline) }
    }
    private func showBrowser() {
        guard let store else { return }
        for (id, item) in items {
            if item.homeSnapshot { item.removeFromSuperview(); items.removeValue(forKey: id); continue }
            item.updatePictureInPicture(store.tabs.first(where: { $0.id == id })?.isPictureInPicture == true)
            let selected = id == store.selectedID && store.selectedTab?.hasContent == true
            let capturing = store.tabs.first(where: { $0.id == id })?.isCapturingPreview == true
            if selected || capturing {
                item.setViewport(bounds.size); item.place(in: bounds, radius: 0)
                item.crop(to: nil); item.alpha = 1
            } else {
                // A full-size 1%-opaque page must not bleed through the grid.
                // Mask its pixels, leaving the original live view mounted.
                item.crop(to: .zero); item.alpha = 0.01
            }
        }
        outline.alpha = 0
        raiseSelectedAndOutline()
    }
    func hasLivePreview(_ id: UUID) -> Bool {
        guard let tab = store?.tabs.first(where: { $0.id == id }) else { return false }
        return items[id]?.homeSnapshot == true || (tab.isLive && tab.hasContent && !tab.pageUnavailable && (id == store?.selectedID || tab.isProtectedForMedia))
    }
    func captureHomePreview() {
        guard let store, let tab = store.selectedTab, !tab.hasContent,
              UIApplication.shared.applicationState == .active, let root = window?.rootViewController?.view,
              bounds.width > 1, bounds.height > 1 else { return }
        // Current native Home UI only; no media/private WK snapshot or disk IO.
        let rect = convert(bounds, to: root)
        guard let snapshot = root.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return }
        items.removeValue(forKey: tab.id)?.removeFromSuperview()
        let item = LiveTabCanvasItem(content: snapshot, homeSnapshot: true)
        items[tab.id] = item; addSubview(item); item.setViewport(bounds.size)
        item.place(in: bounds, radius: 0); raiseSelectedAndOutline()
    }
    private func placeCard(_ item: LiveTabCanvasItem, rect: CGRect, viewport: CGRect) {
        item.place(in: rect, radius: 14)
        item.crop(to: viewport.intersection(bounds)); item.alpha = 1
    }
    func showOverview(frames: [UUID: CGRect], cards: [UUID: CGRect], viewport: CGRect, duration: Double,
                      completion: ((Bool) -> Void)? = nil) {
        guard window != nil, let store, !animating else { completion?(false); return }
        let previews = frames.mapValues { convert($0, from: nil) }
        let cards = cards.mapValues { convert($0, from: nil) }
        let crop = convert(viewport, from: nil).intersection(bounds)
        let selected = store.selectedID
        // Settle every other live card immediately, before starting the one
        // selected-page animation. They never grow/shrink with that page.
        UIView.performWithoutAnimation {
            for (id, item) in items where duration == 0 || id != selected {
                if hasLivePreview(id), let rect = previews[id], rect.intersects(crop) {
                    placeCard(item, rect: rect, viewport: crop)
                } else { item.crop(to: .zero); item.alpha = item.homeSnapshot ? 0 : 0.01 }
            }
        }
        outline.layer.borderColor = (store.selectedTab?.isPrivate == true ? UIColor.systemPurple : .systemBlue)
            .resolvedColor(with: traitCollection).cgColor
        guard let selected, let fullCard = cards[selected] else { outline.alpha = 0; completion?(true); return }
        raiseSelectedAndOutline()
        if duration == 0 {
            UIView.performWithoutAnimation { outline.frame = fullCard; outline.layer.cornerRadius = 14; outline.alpha = 1; outline.crop(to: crop) }
            completion?(true); return
        }
        guard let item = items[selected], let rect = previews[selected] else { completion?(true); return }
        UIView.performWithoutAnimation {
            item.crop(to: nil); outline.crop(to: nil)
            outline.frame = item.frame; outline.layer.cornerRadius = 0; outline.alpha = 0
        }
        animating = true
        beginProbe(selected: selected, opening: true)
        UIView.animate(withDuration: duration, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
            item.place(in: rect, radius: 14)
            self.outline.frame = fullCard; self.outline.layer.cornerRadius = 14; self.outline.alpha = 1
        } completion: { finished in
            self.endProbe(); self.animating = false
            item.crop(to: crop); self.outline.crop(to: crop)
            completion?(finished)
        }
    }
    func returnToBrowser(duration: Double, completion: @escaping () -> Void) {
        guard let store, let selected = store.selectedTab else { completion(); return }
        let geometry = TabOverviewPresentation.shared
        if items[selected.id] == nil {
            let content: UIView
            if selected.hasContent { content = selected.webView }
            else {
                let label = UILabel(); label.text = "新しいタブ"; label.textAlignment = .center
                label.backgroundColor = .systemBackground; label.textColor = .secondaryLabel; content = label
            }
            let item = LiveTabCanvasItem(content: content, homeSnapshot: !selected.hasContent)
            items[selected.id] = item; addSubview(item); item.setViewport(bounds.size)
        }
        guard let item = items[selected.id] else { completion(); return }
        if item.alpha < 0.5 || item.isFullyMasked {
            let rect = geometry.frames[selected.id].map { convert($0, from: nil) }
                ?? CGRect(x: bounds.midX, y: bounds.maxY, width: 1, height: 1)
            UIView.performWithoutAnimation { item.place(in: rect, radius: 14); item.alpha = 1; item.crop(to: nil) }
        }
        UIView.performWithoutAnimation {
            outline.frame = geometry.cards[selected.id].map { convert($0, from: nil) } ?? item.frame
            outline.layer.cornerRadius = 14; outline.alpha = 1
        }
        raiseSelectedAndOutline()
        animating = true
        beginProbe(selected: selected.id, opening: false)
        item.expandCrop(to: bounds, duration: duration)
        outline.expandCrop(to: bounds.size, duration: duration)
        UIView.animate(withDuration: duration, delay: 0, options: [.allowUserInteraction, .curveEaseInOut]) {
            item.place(in: self.bounds, radius: 0)
            self.outline.frame = self.bounds; self.outline.layer.cornerRadius = 0; self.outline.alpha = 0
        } completion: { _ in
            self.endProbe(); self.animating = false
            item.crop(to: nil); self.outline.crop(to: nil)
            // Only now may a different orientation/keyboard viewport reflow.
            item.setViewport(self.bounds.size); item.place(in: self.bounds, radius: 0)
            completion()
        }
    }
    private func beginProbe(selected: UUID, opening: Bool) {
        #if DEBUG
        guard OverviewMotionDiagnostics.fixture else { return }
        motionProbe = OverviewMotionProbe(opening: opening) { [weak self] in
            guard let self, let item = self.items[selected] else { return nil }
            return OverviewMotionProbe.Sample(
                frame: item.layer.presentation()?.frame ?? item.frame,
                content: ObjectIdentifier(item.content), viewport: item.content.bounds, transform: item.content.transform,
                scroll: (item.content as? WKWebView)?.scrollView.contentOffset ?? .zero,
                peers: self.items.filter { $0.key != selected && $0.value.alpha > 0.5 && !$0.value.isFullyMasked }
                    .mapValues { $0.layer.presentation()?.frame ?? $0.frame },
                outlineOnTop: self.subviews.last === self.outline)
        }
        motionProbe?.start()
        #endif
    }
    private func endProbe() {
        #if DEBUG
        motionProbe?.finish(); motionProbe = nil
        #endif
    }
}

@MainActor
private final class LiveTabCanvasItem: UIView {
    let content: UIView
    let homeSnapshot: Bool
    private var viewport = CGSize.zero
    private var restoreViewport = false
    private var fullscreenObservation: NSKeyValueObservation?
    private var reportedPiP = false
    private var protectsPiPViewport = false
    private var pipReleaseScheduled = false
    private let cropLayer = CAShapeLayer()
    private(set) var isFullyMasked = false
    init(content: UIView, homeSnapshot: Bool) {
        self.content = content; self.homeSnapshot = homeSnapshot
        super.init(frame: .zero); clipsToBounds = true; isOpaque = false; autoresizesSubviews = false
        content.autoresizingMask = []; addSubview(content)
        if let view = content as? WKWebView {
            fullscreenObservation = view.observe(\.fullscreenState, options: [.new]) { [weak self] _, change in
                guard let state = change.newValue else { return }
                // WebKit moves its WebView into its own fullscreen window and
                // restores the original placeholder itself. Never steal it.
                Task { @MainActor in
                    guard let self else { return }
                    if state != .notInFullscreen { self.restoreViewport = true }
                    else if self.restoreViewport { self.superview?.setNeedsLayout() }
                }
            }
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func updatePictureInPicture(_ active: Bool) {
        reportedPiP = active
        if active { protectsPiPViewport = true }
        else if protectsPiPViewport, !pipReleaseScheduled, UIApplication.shared.applicationState == .active {
            pipReleaseScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.pipReleaseScheduled = false
                guard !self.reportedPiP, UIApplication.shared.applicationState == .active else { return }
                self.protectsPiPViewport = false
                self.superview?.setNeedsLayout()
            }
        }
    }
    func setViewport(_ size: CGSize) {
        guard !protectsPiPViewport else { return }
        guard size.width > 0, size.height > 0 else { return }
        guard ownsLayout else { restoreViewport = true; return }
        guard viewport != size || restoreViewport else { return }
        restoreViewport = false
        viewport = size
        // No transform is ever applied to the WebView itself for an overview.
        content.transform = .identity; content.bounds = CGRect(origin: .zero, size: size)
        content.center = CGPoint(x: size.width / 2, y: size.height / 2)
    }
    func place(in rect: CGRect, radius: CGFloat) {
        guard ownsLayout, viewport.width > 0, rect.width > 0, rect.height > 0 else { return }
        let scale = rect.width / viewport.width
        let nextBounds = CGRect(x: 0, y: 0, width: viewport.width, height: rect.height / scale)
        let nextCenter = CGPoint(x: rect.midX, y: rect.midY)
        let nextTransform = CGAffineTransform(scaleX: scale, y: scale)
        let corners: CACornerMask = radius > 0 ? [.layerMinXMaxYCorner, .layerMaxXMaxYCorner] : []
        if bounds != nextBounds { bounds = nextBounds }
        if center != nextCenter { center = nextCenter }
        if transform != nextTransform { transform = nextTransform }
        if layer.cornerRadius != radius / scale { layer.cornerRadius = radius / scale }
        if layer.maskedCorners != corners { layer.maskedCorners = corners }
    }
    private var ownsLayout: Bool {
        guard let view = content as? WKWebView else { return true }
        return view.fullscreenState == .notInFullscreen && view.superview === self
    }
    func crop(to rect: CGRect?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let rect, let parent = superview {
            let local = rect.isEmpty ? CGRect.zero : convert(rect, from: parent).intersection(bounds)
            cropLayer.path = UIBezierPath(rect: local.isNull ? .zero : local).cgPath
            layer.mask = cropLayer; isFullyMasked = local.isEmpty || local.isNull
        } else { layer.mask = nil; isFullyMasked = false }
        CATransaction.commit()
    }
    func expandCrop(to rect: CGRect, duration: Double) {
        guard layer.mask != nil, viewport.width > 0, rect.width > 0 else { return }
        let target = CGRect(x: 0, y: 0, width: viewport.width, height: rect.height * viewport.width / rect.width)
        let previous = cropLayer.presentation()?.path ?? cropLayer.path
        cropLayer.path = UIBezierPath(rect: target).cgPath
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "path"); animation.fromValue = previous; animation.toValue = cropLayer.path
            animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cropLayer.add(animation, forKey: "reveal")
        }
    }
}

@MainActor
private final class TabSelectionOutlineView: UIView {
    private let cropLayer = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = .clear; layer.borderWidth = 3; layer.cornerRadius = 14
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func crop(to rect: CGRect?) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if let rect, let parent = superview {
            let local = convert(rect, from: parent).intersection(bounds)
            cropLayer.path = UIBezierPath(rect: local.isNull ? .zero : local).cgPath; layer.mask = cropLayer
        } else { layer.mask = nil }
        CATransaction.commit()
    }
    func expandCrop(to size: CGSize, duration: Double) {
        guard layer.mask != nil else { return }
        let previous = cropLayer.presentation()?.path ?? cropLayer.path
        cropLayer.path = UIBezierPath(rect: CGRect(origin: .zero, size: size)).cgPath
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "path"); animation.fromValue = previous; animation.toValue = cropLayer.path
            animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            cropLayer.add(animation, forKey: "reveal")
        }
    }
}
