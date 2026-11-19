import UIKit
import WebKit

/// Each WebView is mounted once in its own clipping view. Overview changes only
/// UIKit transforms/frames; it never replaces the player or resizes its viewport.
@MainActor
final class WebSurfaceView: UIView {
    let chromeRecovery = ChromeRecoveryObserver()
    private weak var store: BrowserStore?
    private var items: [UUID: LiveTabCanvasItem] = [:]
    private let clip = CAShapeLayer()
    private var animating = false
    override init(frame: CGRect) {
        super.init(frame: frame); clipsToBounds = true; isOpaque = false; backgroundColor = .clear
        chromeRecovery.install(on: self)
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
                items[tab.id] = item; addSubview(item)
                item.setViewport(bounds.size)
            }
            let interactive = !store.overviewPresented && tab.id == store.selectedID && tab.hasContent
            let hidden = store.overviewPresented || tab.id != store.selectedID
            if webView.isUserInteractionEnabled != interactive { webView.isUserInteractionEnabled = interactive }
            if webView.accessibilityElementsHidden != hidden { webView.accessibilityElementsHidden = hidden }
        }
        if let selected = store.selectedID, let item = items[selected], subviews.last !== item { bringSubviewToFront(item) }
        if !store.overviewPresented {
            for (id, item) in items {
                if item.homeSnapshot { item.removeFromSuperview(); items.removeValue(forKey: id); continue }
                if item.frame != bounds { item.frame = bounds }
                if item.layer.cornerRadius != 0 { item.layer.cornerRadius = 0 }
                item.setViewport(bounds.size)
                let capturing = store.tabs.first(where: { $0.id == id })?.isCapturingPreview == true
                let alpha: CGFloat = (id == store.selectedID && store.selectedTab?.hasContent == true) || capturing ? 1 : 0.01
                if item.alpha != alpha { item.alpha = alpha }
            }
            if layer.mask != nil { layer.mask = nil }
        } else { TabOverviewPresentation.shared.synchronize() }
        chromeRecovery.webView = store.overviewPresented ? nil : store.selectedTab?.existingWebView
        chromeRecovery.hidden = { [weak store] in store?.chromeVisible == false }
        chromeRecovery.locked = { [weak store] in store?.selectedTab?.documentScrollLocked == true }
        chromeRecovery.reveal = { [weak store] in store?.revealChrome() }
        chromeRecovery.updateEnabled()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !animating, let store else { return }
        if !store.overviewPresented {
            for item in items.values {
                if item.frame != bounds { item.frame = bounds }
                item.setViewport(bounds.size)
            }
        } else { TabOverviewPresentation.shared.synchronize() }
    }
    func hasLivePreview(_ id: UUID) -> Bool {
        guard let tab = store?.tabs.first(where: { $0.id == id }) else { return false }
        return items[id]?.homeSnapshot == true || (tab.isLive && tab.hasContent && !tab.pageUnavailable && (id == store?.selectedID || tab.isProtectedForMedia || tab.isCapturingPreview))
    }
    func captureHomePreview() {
        guard let store, let tab = store.selectedTab, !tab.hasContent,
              UIApplication.shared.applicationState == .active, let root = window?.rootViewController?.view,
              bounds.width > 1, bounds.height > 1 else { return }
        // Own, currently visible Home UI only. No WK snapshot, active video
        // snapshot or disk/private-preview write participates in this transition.
        let rect = convert(bounds, to: root)
        guard let snapshot = root.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero) else { return }
        items.removeValue(forKey: tab.id)?.removeFromSuperview()
        let item = LiveTabCanvasItem(content: snapshot, homeSnapshot: true)
        items[tab.id] = item; addSubview(item); item.frame = bounds; item.setViewport(bounds.size)
    }
    func showOverview(frames: [UUID: CGRect], viewport: CGRect, duration: Double, completion: ((Bool) -> Void)? = nil) {
        guard window != nil, let store else { completion?(false); return }
        let crop = convert(viewport, from: nil).intersection(bounds)
        let visible = frames.filter { self.hasLivePreview($0.key) }.mapValues { self.convert($0, from: nil).intersection(crop).intersection(self.bounds) }
        let ordered = visible.keys.sorted { $0.uuidString < $1.uuidString }
        let from = UIBezierPath(), to = UIBezierPath()
        for id in ordered {
            guard let rect = visible[id], !rect.isNull else { continue }
            to.append(UIBezierPath(rect: rect))
            let start = id == store.selectedID ? bounds : CGRect(x: rect.midX, y: rect.midY, width: 0, height: 0)
            from.append(UIBezierPath(rect: start))
        }
        clip.frame = bounds; clip.path = to.cgPath; layer.mask = clip
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "path"); animation.fromValue = from.cgPath; animation.toValue = to.cgPath
            animation.duration = duration; animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            clip.add(animation, forKey: "overviewClip")
        }
        let changes = {
            for (id, item) in self.items {
                if self.hasLivePreview(id), let rect = frames[id] {
                    item.frame = self.convert(rect, from: nil); item.layer.cornerRadius = 12
                    item.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
                    item.alpha = 1; item.fitPreview()
                } else { item.alpha = item.homeSnapshot ? 0 : 0.01 }
            }
            if let id = store.selectedID, let selected = self.items[id] { self.bringSubviewToFront(selected) }
        }
        if duration == 0 { UIView.performWithoutAnimation(changes); completion?(true); return }
        animating = true
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: changes) { finished in
            self.animating = false; completion?(finished)
        }
    }
    func returnToBrowser(duration: Double, completion: @escaping () -> Void) {
        guard let store, let selected = store.selectedTab else { completion(); return }
        if items[selected.id] == nil {
            let content: UIView
            if selected.hasContent { content = selected.webView }
            else {
                let label = UILabel(); label.text = "新しいタブ"; label.textAlignment = .center
                label.backgroundColor = .systemBackground; label.textColor = .secondaryLabel; content = label
            }
            let item = LiveTabCanvasItem(content: content, homeSnapshot: !selected.hasContent)
            items[selected.id] = item; addSubview(item); item.setViewport(bounds.size)
            if let rect = TabOverviewPresentation.shared.frames[selected.id] { item.frame = convert(rect, from: nil); item.fitPreview() }
            else { item.frame = CGRect(x: bounds.midX, y: bounds.maxY, width: 1, height: 1); item.fitPreview() }
        }
        guard let selectedItem = items[selected.id] else { completion(); return }
        bringSubviewToFront(selectedItem)
        if selectedItem.alpha < 0.5, let rect = TabOverviewPresentation.shared.frames[selected.id] {
            UIView.performWithoutAnimation {
                selectedItem.frame = self.convert(rect, from: nil); selectedItem.fitPreview(); selectedItem.alpha = 1
            }
        }
        let startRect = selectedItem.frame.intersection(bounds)
        let from = UIBezierPath(rect: startRect.isNull ? CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1) : startRect)
        let to = UIBezierPath(rect: bounds)
        for (id, item) in items where id != selected.id && item.alpha > 0.5 {
            let rect = item.frame.intersection(bounds)
            if !rect.isNull {
                from.append(UIBezierPath(rect: rect))
                to.append(UIBezierPath(rect: CGRect(x: rect.midX, y: rect.midY, width: 0, height: 0)))
            }
        }
        clip.frame = bounds; clip.path = to.cgPath; layer.mask = clip
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "path"); animation.fromValue = from.cgPath; animation.toValue = to.cgPath
            animation.duration = duration; clip.add(animation, forKey: "overviewClip")
        }
        animating = true
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            selectedItem.frame = self.bounds; selectedItem.layer.cornerRadius = 0
            selectedItem.alpha = 1; selectedItem.setViewport(self.bounds.size)
            for (id, item) in self.items where id != selected.id { item.alpha = item.homeSnapshot ? 0 : 0.01 }
        } completion: { _ in self.animating = false; self.layer.mask = nil; completion() }
    }
}

@MainActor
private final class LiveTabCanvasItem: UIView {
    let content: UIView
    let homeSnapshot: Bool
    private var viewport = CGSize.zero
    private var previewing = false
    init(content: UIView, homeSnapshot: Bool) {
        self.content = content; self.homeSnapshot = homeSnapshot
        super.init(frame: .zero); clipsToBounds = true; isOpaque = false; autoresizesSubviews = false
        content.autoresizingMask = []; addSubview(content)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func setViewport(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // Metadata/preview updates must not reset an unchanged WK viewport or
        // interrupt UIKit's ongoing link/image context-menu presentation.
        guard viewport != size || previewing else { return }
        previewing = false
        viewport = size; content.transform = .identity
        content.bounds = CGRect(origin: .zero, size: size); content.center = center
    }
    func fitPreview() {
        guard viewport.width > 0, viewport.height > 0 else { return }
        previewing = true
        let scale = bounds.width / viewport.width
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
        content.center = CGPoint(x: bounds.width / 2, y: viewport.height * scale / 2)
    }
}
