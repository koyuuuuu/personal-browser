import UIKit

/// Give WebKit's native previews and menus a concrete UIKit presentation owner.
/// SwiftUI retains this controller and the same canvas across tab changes.
@MainActor
final class WebSurfaceController: UIViewController {
    let surface = WebSurfaceView(frame: .zero)
    override func loadView() { view = surface }
}
