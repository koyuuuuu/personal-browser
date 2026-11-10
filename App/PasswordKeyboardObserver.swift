import SwiftUI
import UIKit

/// Observe the public guide; SwiftUI alone owns keyboard avoidance. No offsets
/// are added here, avoiding a second keyboard-height subtraction.
struct PasswordKeyboardObserver: UIViewRepresentable {
    let changed: (Bool) -> Void
    func makeUIView(context: Context) -> GuideView {
        let view = GuideView(); view.changed = changed; return view
    }
    func updateUIView(_ view: GuideView, context: Context) { view.changed = changed }
    final class GuideView: UIView {
        var changed: ((Bool) -> Void)?
        private var last: Bool?
        private let marker = UIView()
        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            marker.translatesAutoresizingMaskIntoConstraints = false; addSubview(marker)
            NSLayoutConstraint.activate([
                marker.topAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
                marker.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.bottomAnchor),
                marker.leadingAnchor.constraint(equalTo: leadingAnchor), marker.widthAnchor.constraint(equalToConstant: 1)
            ])
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func layoutSubviews() {
            super.layoutSubviews()
            let value = keyboardLayoutGuide.layoutFrame.height > safeAreaInsets.bottom + 70
            guard value != last else { return }; last = value
            DispatchQueue.main.async { [weak self] in self?.changed?(value) }
        }
    }
}
