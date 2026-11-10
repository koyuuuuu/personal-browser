import SwiftUI
import WebKit
import CoreMotion

@MainActor
final class BrowserOrientationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        VideoOrientationController.shared.mask
    }
}

@MainActor
final class VideoOrientationController: ObservableObject {
    static let shared = VideoOrientationController()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "browser.videoOrientation.v1")
    @Published private(set) var message: String?
    private(set) var mask: UIInterfaceOrientationMask = .allButUpsideDown
    private let motion = CMMotionManager()
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var selectedID: UUID?
    private var allowed = true
    private var foreground = true
    private var tilt: VideoTilt = .portrait
    private var lastLandscape: VideoTilt = .landscapeRight
    private var pendingTilt: VideoTilt?
    private var pendingSince = Date.distantPast
    private var attempted = false
    private var original: UIInterfaceOrientation?
    private weak var orientedScene: UIWindowScene?
    private var orientationGeneration = 0
    private var rejectedMask: UIInterfaceOrientationMask?
    private final class Entry {
        weak var view: WKWebView?
        let tabID: UUID
        var frames: [String: Frame] = [:]
        init(_ view: WKWebView, tabID: UUID) { self.view = view; self.tabID = tabID }
    }
    private struct Frame {
        let info: WKFrameInfo
        let videos: [[String: Any]]
    }
    func attach(_ view: WKWebView, tabID: UUID) {
        entries[ObjectIdentifier(view)] = Entry(view, tabID: tabID)
        let content = view.configuration.userContentController
        content.add(VideoOrientationHandler(owner: self), contentWorld: .defaultClient, name: "browserVideoOrientation")
        content.addUserScript(script())
    }
    func detach(_ view: WKWebView) {
        reset(view); entries.removeValue(forKey: ObjectIdentifier(view))
        view.configuration.userContentController.removeScriptMessageHandler(forName: "browserVideoOrientation", contentWorld: .defaultClient)
    }
    func reset(_ view: WKWebView) {
        if entries[ObjectIdentifier(view)]?.tabID == selectedID { restore(); attempted = false }
        entries[ObjectIdentifier(view)]?.frames.removeAll()
        updateMotion()
    }
    private func script() -> WKUserScript {
        WKUserScript(source: VideoOrientationScript.source(enabled: enabled), injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient)
    }
    func setEnabled(_ value: Bool) {
        enabled = value; message = nil
        UserDefaults.standard.set(value, forKey: "browser.videoOrientation.v1")
        for entry in entries.values {
            guard let view = entry.view else { continue }
            let content = view.configuration.userContentController
            let others = content.userScripts.filter { !$0.source.contains("if (globalThis.__personalBrowserVideo) return;") }
            content.removeAllUserScripts(); others.forEach(content.addUserScript); content.addUserScript(script())
        }
        context(selected: selectedID, allowed: allowed)
    }
    func context(selected: UUID?, allowed: Bool) {
        if selectedID != selected || !allowed || !enabled { restore(); attempted = false }
        selectedID = selected; self.allowed = allowed
        for entry in entries.values {
            guard let view = entry.view else { continue }
            let visible = foreground && allowed && entry.tabID == selected
            configureVideoOrientation(view, frame: nil, enabled: enabled, active: visible)
            for frame in entry.frames.values where !frame.info.isMainFrame {
                configureVideoOrientation(view, frame: frame.info, enabled: enabled, active: visible)
            }
        }
        updateMotion()
    }
    func sceneChanged(_ phase: ScenePhase) {
        foreground = phase == .active
        if phase == .background { restore(); attempted = false }
        context(selected: selectedID, allowed: allowed)
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard let view = message.webView, let entry = entries[ObjectIdentifier(view)],
              let body = message.body as? [String: Any], let doc = body["document"] as? String, doc.count <= 64,
              let videos = body["videos"] as? [[String: Any]] else { return }
        if body["gone"] as? Bool == true { entry.frames.removeValue(forKey: doc); reconcile(); updateMotion(); return }
        guard entry.frames[doc] != nil || entry.frames.count < 32 else { return }
        entry.frames[doc] = Frame(info: message.frameInfo, videos: Array(videos.prefix(16)))
        let visible = foreground && allowed && entry.tabID == selectedID
        if !enabled || !visible {
            configureVideoOrientation(view, frame: message.frameInfo, enabled: enabled, active: false)
            return
        }
        reconcile(); updateMotion()
    }
    private var selectedEntry: Entry? { entries.values.first { $0.tabID == selectedID && $0.view != nil } }
    private func updateMotion() {
        let needed = enabled && foreground && allowed && selectedEntry?.frames.values.contains(where: { $0.videos.contains { ($0["area"] as? Double ?? 0) >= 6400 || $0["fullscreen"] as? Bool == true } }) == true
        if needed && !motion.isDeviceMotionActive && motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 0.15
            motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, _ in
                guard let gravity = sample?.gravity else { return }
                Task { @MainActor in self?.sample(x: gravity.x, y: gravity.y, z: gravity.z) }
            }
        } else if !needed { motion.stopDeviceMotionUpdates(); pendingTilt = nil }
    }
    private func sample(x: Double, y: Double, z: Double, now: Date = Date()) {
        guard enabled && foreground && allowed, let next = VideoTilt.gravity(x: x, y: y, z: z) else { return }
        if pendingTilt != next { pendingTilt = next; pendingSince = now; return }
        guard now.timeIntervalSince(pendingSince) >= 0.45, next != tilt else { return }
        tilt = next
        if next != .portrait { lastLandscape = next }
        if next == .portrait { attempted = false }
        reconcile()
    }
    private func reconcile() {
        guard enabled && foreground && allowed, let entry = selectedEntry, let view = entry.view else { return }
        let all = entry.frames.flatMap { doc, frame in frame.videos.map { (doc, frame.info, $0) } }
        if let full = all.first(where: { $0.2["fullscreen"] as? Bool == true }),
           let width = full.2["width"] as? Double, let height = full.2["height"] as? Double,
           let direction = VideoTilt.forVideo(width: width, height: height, tilt: tilt == .portrait ? lastLandscape : tilt) {
            attempted = true
            orient(direction, scene: view.window?.windowScene)
            return
        }
        if original != nil { restore() }
        guard tilt != .portrait, !attempted else { return }
        // Embedded players must already be playing. IntersectionObserver in
        // each frame accounts for clipping by the top-level viewport.
        let eligible = all.filter { item in
            let v = item.2
            return (item.1.isMainFrame || v["playing"] as? Bool == true) && v["supported"] as? Bool == true && v["pip"] as? Bool != true && v["paused"] as? Bool != true &&
                (v["area"] as? Double ?? 0) >= 6400 && (v["width"] as? Double ?? 0) > 0 && (v["height"] as? Double ?? 0) > 0
        }.sorted { ($0.2["area"] as? Double ?? 0) > ($1.2["area"] as? Double ?? 0) }
        guard let chosen = eligible.first, eligible.count == 1 || (chosen.2["area"] as? Double ?? 0) > (eligible[1].2["area"] as? Double ?? 0) * 2,
              let id = chosen.2["id"] as? String else { return }
        attempted = true
        enterVideoFullscreen(view, frame: chosen.1, document: chosen.0, video: id)
    }
    private func orient(_ direction: VideoTilt, scene: UIWindowScene?) {
        guard let scene else { return }
        let next: UIInterfaceOrientationMask = direction == .portrait ? .portrait : direction == .landscapeLeft ? .landscapeLeft : .landscapeRight
        guard next != mask, next != rejectedMask else { return }
        if original == nil { original = scene.interfaceOrientation; orientedScene = scene }
        mask = next; updateControllers(scene)
        orientationGeneration += 1; let generation = orientationGeneration
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: next)) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.orientationGeneration == generation else { return }
                self.message = "この動画またはiOSが画面方向の変更を許可しませんでした。通常の全画面ボタンもお試しください。"
                self.rejectedMask = next
                self.mask = .allButUpsideDown; self.updateControllers(scene)
            }
        }
    }
    private func updateControllers(_ scene: UIWindowScene) {
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller { current.setNeedsUpdateOfSupportedInterfaceOrientations(); controller = current.presentedViewController }
        }
    }
    private func restore() {
        orientationGeneration += 1
        mask = .allButUpsideDown
        if let scene = orientedScene {
            updateControllers(scene)
            if foreground, let original {
                let target: UIInterfaceOrientationMask = original == .landscapeLeft ? .landscapeLeft : original == .landscapeRight ? .landscapeRight : .portrait
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: target)) { _ in }
            }
        }
        original = nil; orientedScene = nil; rejectedMask = nil
    }
    #if DEBUG
    static var fixture: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--ui-video-orientation-fixture")
    }
    func fixtureTilt(horizontal: Bool) {
        guard Self.fixture else { return }
        let start = Date()
        sample(x: horizontal ? -1 : 0, y: horizontal ? 0 : -1, z: 0, now: start)
        sample(x: horizontal ? -1 : 0, y: horizontal ? 0 : -1, z: 0, now: start.addingTimeInterval(0.6))
    }
    #endif
}

@MainActor
private final class VideoOrientationHandler: NSObject, WKScriptMessageHandler {
    weak var owner: VideoOrientationController?
    init(owner: VideoOrientationController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}

@MainActor
struct VideoOrientationSettingsView: View {
    @ObservedObject private var controller = VideoOrientationController.shared
    var body: some View {
        Form {
            Section {
                Toggle("動画の自動全画面・向き調整", isOn: Binding(get: { controller.enabled }, set: controller.setEnabled))
                    .accessibilityIdentifier("videoOrientationToggle")
            } footer: {
                Text("横に傾けると、表示中の動画を全画面にします。横長の動画は横向き、縦長・正方形は縦向きで表示します。一時停止した動画は再開しません。初期設定はオフです。")
            }
            Section {
                Text("iOS全体の縦向きロックは変更せず、動画の全画面中だけアプリの向きを指定します。iOSやサイトの制限により、先に再生・全画面ボタンを押す必要がある場合があります。字幕や操作部を含め、動画の表示方法はサイトと標準プレーヤーに従います。")
                if let message = controller.message { Text(message) }
            }
        }.navigationTitle("動画の全画面・向き")
    }
}
