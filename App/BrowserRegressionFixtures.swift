#if DEBUG
import SwiftUI
import UIKit
import WebKit

@MainActor
enum BrowserRegressionFixtures {
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

@MainActor
final class PhotoSaveFixture: NSObject, ObservableObject {
    static let shared = PhotoSaveFixture()
    @Published private(set) var status = "Photo not saved"
    @Published private(set) var busy = false
    func save(tab: BrowserTab?) {
        let url = URL(string: "http://127.0.0.1:18765/photo-fixture")!
        guard BrowserRegressionFixtures.kind == "photo-fixture", !busy, let tab,
              !tab.isPrivate, !tab.isProtectedForMedia, let view = tab.existingWebView,
              view.url == url, view.window != nil, UIApplication.shared.applicationState == .active else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 28, y: 20, width: 240, height: 160)
        guard view.bounds.contains(configuration.rect) else { return }
        busy = true; status = "Loading photo"
        // This fixed foreground fixture contains only the known image, no media
        // or user data. No private/inactive page or video is snapshotted.
        view.takeSnapshot(with: configuration) { [weak self, weak view] image, error in
            Task { @MainActor in
                guard let self else { return }
                guard error == nil, let image, let view, view.url == url,
                      view.window != nil, UIApplication.shared.applicationState == .active else {
                    self.status = "Photo fixture failed"; self.busy = false; return
                }
                self.status = "Saving photo"
                // Exercise the real OS photo writer and its TCC purpose checks.
                // No authorization bypass or photo-library reading is involved.
                UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.saved(_:didFinishSavingWithError:contextInfo:)), nil)
            }
        }
    }
    @objc nonisolated private func saved(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        let succeeded = error == nil
        Task { @MainActor [weak self] in
            self?.status = succeeded ? "Photo saved" : "Photo save failed"
            self?.busy = false
        }
    }
}

@MainActor
struct BrowserRegressionFixtureControls: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject private var photos = PhotoSaveFixture.shared
    var body: some View {
        if BrowserRegressionFixtures.kind == "session-login" {
            Button("読み込み済み8ページを開く") { BrowserRegressionFixtures.openCachedPages(store) }
                .accessibilityIdentifier("openCachedPagesFixtureButton")
                .font(.caption).buttonStyle(.borderedProminent).padding(4)
        } else if BrowserRegressionFixtures.kind == "photo-fixture" {
            VStack {
                Button("写真に保存（検証）") { photos.save(tab: store.selectedTab) }
                    .accessibilityIdentifier("saveWebsitePhotoFixtureButton").disabled(photos.busy)
                Text(photos.status).accessibilityIdentifier("photoSaveResult")
            }.font(.caption).padding(4)
        }
    }
}
#endif
