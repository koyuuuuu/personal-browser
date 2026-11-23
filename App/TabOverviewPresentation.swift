import SwiftUI
import UIKit

/// One in-window transition. Geometry goes directly from the collection to the
/// persistent canvas, avoiding SwiftUI updates for every scrolling frame.
@MainActor
final class TabOverviewPresentation: ObservableObject {
    static let shared = TabOverviewPresentation()
    enum Phase: Equatable { case browsing, opening, overview, closing }
    @Published private(set) var phase = Phase.browsing
    var isPresented: Bool { phase != .browsing }
    var duration: Double { UIAccessibility.isReduceMotionEnabled ? 0 : 0.28 }
    weak var surface: WebSurfaceView?
    private weak var store: BrowserStore?
    private var generation = 0
    private var entered = false
    private(set) var frames: [UUID: CGRect] = [:]
    private(set) var cards: [UUID: CGRect] = [:]
    private(set) var viewport = CGRect.zero

    func open(_ store: BrowserStore) {
        guard phase == .browsing else { return }
        self.store = store; generation += 1; entered = false
        frames.removeAll(); cards.removeAll(); viewport = .zero
        surface?.captureHomePreview()
        store.selectedTab?.existingWebView?.endEditing(true)
        withAnimation(.easeInOut(duration: duration)) {
            store.overviewPresented = true; phase = .opening
        }
    }
    func report(frames: [UUID: CGRect], cards: [UUID: CGRect], viewport: CGRect) {
        guard isPresented, phase != .closing, let store, let surface else { return }
        self.frames = frames; self.cards = cards; self.viewport = viewport
        if phase == .opening {
            guard !entered, let selected = store.selectedID, frames[selected] != nil, cards[selected] != nil else { return }
            entered = true
            let token = generation
            // Collection layout may publish repeatedly in one run-loop turn.
            // Use the settled geometry once; never restart an in-flight morph.
            DispatchQueue.main.async { [weak self, weak surface] in
                guard let self, let surface, self.generation == token, self.phase == .opening else { return }
                surface.showOverview(frames: self.frames, cards: self.cards, viewport: self.viewport, duration: self.duration) { [weak self] finished in
                    guard let self, finished, self.generation == token, self.phase == .opening else { return }
                    self.phase = .overview
                    self.synchronize()
                }
            }
        } else {
            surface.showOverview(frames: frames, cards: cards, viewport: viewport, duration: 0)
        }
    }
    func synchronize() {
        guard entered, phase == .overview else { return }
        surface?.showOverview(frames: frames, cards: cards, viewport: viewport, duration: 0)
    }
    func close() {
        guard phase == .overview, let store else { return }
        generation += 1; let token = generation
        withAnimation(.easeInOut(duration: duration)) { phase = .closing }
        surface?.synchronize(store)
        let finish = { [weak self, weak store] in
            guard let self, let store, self.generation == token else { return }
            store.overviewPresented = false
            self.phase = .browsing; self.frames.removeAll(); self.cards.removeAll(); self.viewport = .zero; self.entered = false
            self.surface?.synchronize(store)
        }
        if let surface { surface.returnToBrowser(duration: duration, completion: finish) }
        else { finish() }
    }
}
