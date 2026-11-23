#if DEBUG
import SwiftUI
import UIKit

/// Controlled-fixture observations only: no URLs, page text, or credentials.
@MainActor
final class OverviewMotionDiagnostics: ObservableObject {
    static let shared = OverviewMotionDiagnostics()
    static var fixture: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--ui-overview-motion-fixture")
    }
    @Published private(set) var status = "Motion waiting"
    private var opens = 0, closes = 0, samples = 0
    private var frozen = true, stationary = true, monotone = true, onTop = true, sawPeer = false

    func record(opening: Bool, samples: Int, frozen: Bool, stationary: Bool, monotone: Bool, onTop: Bool, sawPeer: Bool) {
        if opening { opens += 1 } else { closes += 1 }
        self.samples += samples
        self.frozen = self.frozen && frozen; self.stationary = self.stationary && stationary
        self.monotone = self.monotone && monotone; self.onTop = self.onTop && onTop; self.sawPeer = self.sawPeer || sawPeer
        status = "Motion open\(opens) close\(closes) samples\(self.samples) frozen\(self.frozen) peers\(self.stationary) monotone\(self.monotone) outline\(self.onTop) observed\(self.sawPeer)"
    }
}

@MainActor
struct OverviewMotionFixtureStatus: View {
    @ObservedObject private var diagnostics = OverviewMotionDiagnostics.shared
    var body: some View {
        Text(diagnostics.status).font(.system(size: 9)).frame(width: 170)
            .background(.background).accessibilityIdentifier("overviewMotionResult")
            .allowsHitTesting(false)
    }
}

/// CADisplayLink reads the actual presentation layers and the original WebView
/// on each rendered frame, rather than inferring continuity from final frames.
@MainActor
final class OverviewMotionProbe: NSObject {
    struct Sample {
        let frame: CGRect
        let content: ObjectIdentifier
        let viewport: CGRect
        let transform: CGAffineTransform
        let scroll: CGPoint
        let peers: [UUID: CGRect]
        let outlineOnTop: Bool
    }
    private let opening: Bool
    private let read: () -> Sample?
    private var link: CADisplayLink?
    private var first: Sample?, previous: Sample?
    private var count = 0
    private var frozen = true, stationary = true, monotone = true, onTop = true, sawPeer = false
    init(opening: Bool, read: @escaping () -> Sample?) { self.opening = opening; self.read = read }
    func start() {
        first = read()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        self.link = link; link.add(to: .main, forMode: .common)
    }
    @objc private func tick() {
        guard let sample = read(), let first else { return }
        count += 1
        frozen = frozen && sample.content == first.content && sample.viewport == first.viewport && sample.transform == first.transform && hypot(sample.scroll.x - first.scroll.x, sample.scroll.y - first.scroll.y) < 1
        onTop = onTop && sample.outlineOnTop
        sawPeer = sawPeer || !sample.peers.isEmpty
        if let previous {
            let delta = sample.frame.width - previous.frame.width
            monotone = monotone && (opening ? delta <= 1.5 : delta >= -1.5)
            // The first tick may precede the initial no-animation transaction.
            if count > 2 {
                for (id, rect) in sample.peers {
                    guard let old = previous.peers[id] else { continue }
                    stationary = stationary && abs(rect.minX - old.minX) < 1 && abs(rect.minY - old.minY) < 1 && abs(rect.width - old.width) < 1 && abs(rect.height - old.height) < 1
                }
            }
        }
        previous = sample
    }
    func finish() {
        tick(); link?.invalidate(); link = nil
        OverviewMotionDiagnostics.shared.record(opening: opening, samples: count, frozen: frozen,
            stationary: stationary, monotone: monotone, onTop: onTop, sawPeer: sawPeer)
    }
}
#endif
