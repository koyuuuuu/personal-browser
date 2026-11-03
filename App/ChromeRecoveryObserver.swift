import UIKit
import WebKit

private final class PassiveChromePan: UIPanGestureRecognizer {
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// Observes the finger on the native ancestor of WKContentView. It remains
/// available when DOM touch handlers / overflow locks prevent scrolling.
@MainActor
final class ChromeRecoveryObserver: NSObject, UIGestureRecognizerDelegate {
    weak var webView: WKWebView?
    var hidden: (() -> Bool)?
    var locked: (() -> Bool)?
    var reveal: (() -> Void)?
    private var startedHidden = false
    private var initialY: CGFloat = 0
    private var travel: CGFloat = 0
    private lazy var pan: UIPanGestureRecognizer = {
        let value = PassiveChromePan(target: self, action: #selector(moved(_:)))
        value.minimumNumberOfTouches = 1; value.maximumNumberOfTouches = 1
        value.cancelsTouchesInView = false
        value.delaysTouchesBegan = false; value.delaysTouchesEnded = false
        value.delegate = self
        return value
    }()
    func install(on host: UIView) { host.addGestureRecognizer(pan) }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.y) > abs(velocity.x) * 1.3
    }
    private func position(_ scroll: UIScrollView) -> CGFloat {
        let extent = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom)
        return min(extent, max(0, scroll.contentOffset.y + scroll.adjustedContentInset.top))
    }
    @objc private func moved(_ gesture: UIPanGestureRecognizer) {
        guard let scroll = webView?.scrollView else { return }
        if gesture.state == .began {
            startedHidden = hidden?() == true; initialY = position(scroll); travel = 0
        }
        travel = max(travel, abs(position(scroll) - initialY))
        guard gesture.state == .ended else { return }
        let delta = gesture.translation(in: gesture.view)
        let scrollable = scroll.isScrollEnabled && scroll.contentSize.height > scroll.bounds.height + 4
        if ChromeRecoveryGesture.shouldReveal(startedHidden: startedHidden, x: Double(delta.x), y: Double(delta.y),
            contentTravel: Double(travel), scrollable: scrollable, locked: locked?() == true) { reveal?() }
    }
}
