#if DEBUG
import SwiftUI
import UIKit
import WebKit

@MainActor
enum BrowserRegressionFixtures {
    static var photoMenuStatus = "Photo menu not requested"
    static var nativePhotoControl: Bool { kind == "photo-fixture" && ProcessInfo.processInfo.arguments.contains("--ui-photo-native-control") }
    static var kind: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing") else { return nil }
        for (flag, path) in [("--ui-session-fixture", "session-login"), ("--ui-photo-fixture", "photo-fixture"), ("--ui-overview-media-fixture", "overview-media")] {
            if args.contains(flag) { return path }
        }
        return nil
    }
    static func openCachedPages(_ store: BrowserStore) {
        guard kind == "session-login", let original = store.selectedTab else { return }
        for index in 1...8 {
            guard let tab = store.newTab(url: URL(string: "http://127.0.0.1:18765/cache-\(index)")) else { break }
            // Make actual resident pages, as eight separate user selections do.
            // This does not change the real eviction policy or its protections.
            _ = tab.webView
        }
        store.select(original)
    }
}

/// A diagnostic control only: no browser scripts, delegate, canvas or credentials.
@MainActor
struct PhotoNativeControlView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsLinkPreview = true
        controller.view = webView
        webView.load(URLRequest(url: URL(string: "http://127.0.0.1:18765/photo-fixture")!))
        return controller
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

@MainActor
struct BrowserRegressionFixtureControls: View {
    @ObservedObject var store: BrowserStore
    @State private var showPhotoStatus = false
    var body: some View {
        if BrowserRegressionFixtures.kind == "session-login" {
            Button("読み込み済み8ページを開く") { BrowserRegressionFixtures.openCachedPages(store) }
                .accessibilityIdentifier("openCachedPagesFixtureButton")
                .font(.caption).buttonStyle(.borderedProminent).padding(4)
        } else if BrowserRegressionFixtures.kind == "photo-fixture" {
            VStack {
                Button("写真メニューの診断") { showPhotoStatus = true }
                    .accessibilityIdentifier("photoMenuProbeButton")
                if showPhotoStatus { Text(BrowserRegressionFixtures.photoMenuStatus).font(.caption) }
            }.font(.caption).padding(4)
        }
    }
}
#endif
