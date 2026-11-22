import AVFoundation
import Combine
import MediaPlayer
import UIKit
import WebKit

/// Keeps the existing, authenticated WebKit player. No media URL extraction,
/// native replacement player, silent audio, private API or permanent retry loop.
@MainActor
final class BackgroundAudioController: ObservableObject {
    static let shared = BackgroundAudioController()
    @Published private(set) var enabled = UserDefaults.standard.object(forKey: "browser.backgroundAudio.v1") as? Bool ?? true
    @Published private(set) var message: String?
    private var selected: UUID?
    private var foreground = true
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var observations: Set<AnyCancellable> = []
    private var recovery = BackgroundAudioRecovery()
    private var session: Session?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var remoteTargets: [(MPRemoteCommand, Any)] = []

    private final class Entry {
        weak var view: WKWebView?
        let tabID: UUID
        var frames: [String: Frame] = [:]
        init(_ view: WKWebView, tabID: UUID) { self.view = view; self.tabID = tabID }
    }
    private struct Frame {
        let info: WKFrameInfo
        let videos: [[String: Any]]
        let updated: TimeInterval
    }
    private struct Session {
        let viewID: ObjectIdentifier
        let document: String
        let frame: WKFrameInfo
        let token: String
    }

    private init() {
        let center = NotificationCenter.default
        center.publisher(for: UIApplication.willResignActiveNotification).sink { [weak self] _ in self?.leaving() }.store(in: &observations)
        center.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] _ in self?.returned() }.store(in: &observations)
        center.publisher(for: AVAudioSession.interruptionNotification).receive(on: DispatchQueue.main).sink { [weak self] note in
            if (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue { self?.cancel() }
        }.store(in: &observations)
        center.publisher(for: AVAudioSession.routeChangeNotification).receive(on: DispatchQueue.main).sink { [weak self] note in
            if (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { self?.cancel() }
        }.store(in: &observations)
        center.publisher(for: AVAudioSession.mediaServicesWereResetNotification).receive(on: DispatchQueue.main).sink { [weak self] _ in self?.cancel() }.store(in: &observations)
    }
    func attach(_ view: WKWebView, tabID: UUID) {
        entries[ObjectIdentifier(view)] = Entry(view, tabID: tabID)
        let content = view.configuration.userContentController
        content.add(BackgroundAudioHandler(owner: self), contentWorld: .defaultClient, name: "browserBackgroundAudio")
        content.addUserScript(WKUserScript(source: BackgroundAudioScript.pauseIntent, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        content.addUserScript(WKUserScript(source: BackgroundAudioScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
    }
    func detach(_ view: WKWebView) {
        reset(view); entries.removeValue(forKey: ObjectIdentifier(view))
        view.configuration.userContentController.removeScriptMessageHandler(forName: "browserBackgroundAudio", contentWorld: .defaultClient)
    }
    func reset(_ view: WKWebView) {
        if session?.viewID == ObjectIdentifier(view) { cancel() }
        entries[ObjectIdentifier(view)]?.frames.removeAll()
    }
    func context(selected: UUID?) {
        guard self.selected != selected else { return }
        cancel(); self.selected = selected
        configureViews()
    }
    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        cancel(); enabled = value; message = nil
        UserDefaults.standard.set(value, forKey: "browser.backgroundAudio.v1")
        configureViews()
    }
    private func configureViews() {
        for entry in entries.values {
            guard let view = entry.view else { continue }
            configureBackgroundAudio(view, frame: nil, enabled: enabled && entry.tabID == selected, foreground: foreground)
            // Subframes receive their configuration on ready/inventory too.
            for frame in entry.frames.values {
                configureBackgroundAudio(view, frame: frame.info, enabled: enabled && entry.tabID == selected, foreground: foreground)
            }
        }
    }
    private func leaving() {
        guard foreground else { return }
        foreground = false
        let now = ProcessInfo.processInfo.systemUptime
        let candidates = entries.flatMap { viewID, entry -> [(ObjectIdentifier, String, Frame, String, Double)] in
            guard enabled, entry.tabID == selected, entry.view?.window != nil else { return [] }
            return entry.frames.flatMap { document, frame in
                guard now - frame.updated < 2 else { return [(ObjectIdentifier, String, Frame, String, Double)]() }
                return frame.videos.compactMap { v in
                    guard v["playing"] as? Bool == true, let id = v["id"] as? String,
                          let area = v["area"] as? Double, area >= 6400 else { return nil }
                    return (viewID, document, frame, id, area)
                }
            }
        }
        configureViews()
        guard let candidate = candidates.max(by: { $0.4 < $1.4 }), let view = entries[candidate.0]?.view else { return }
        let audio = AVAudioSession.sharedInstance()
        guard audio.category != .record, audio.category != .playAndRecord else { return }
        do {
            try audio.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try audio.setActive(true)
        } catch { message = "バックグラウンド用の音声設定を適用できませんでした。"; return }
        let token = UUID().uuidString
        session = Session(viewID: candidate.0, document: candidate.1, frame: candidate.2.info, token: token)
        recovery.arm(token: token, now: now)
        // The top document owns audioSession.type, including iframe players.
        setBackgroundAudioPolicy(view, enabled: true)
        armBackgroundAudio(view, frame: candidate.2.info, document: candidate.1, video: candidate.3, token: token)
        installRemoteCommands()
        // Only complete this short transition; no task renewal/keep-alive.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Video audio transition") { [weak self] in
            Task { @MainActor in self?.endTransition() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            guard self?.session?.token == token else { return }
            self?.endTransition()
        }
    }
    private func returned() {
        foreground = true; cancel(); configureViews()
    }
    private func endTransition() {
        recovery.cancel()
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }
    private func cancel() {
        if let session, let view = entries[session.viewID]?.view {
            stopBackgroundAudio(view, frame: session.frame)
            setBackgroundAudioPolicy(view, enabled: false)
        }
        session = nil; endTransition()
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets.removeAll()
    }
    private func remote(_ action: String) {
        recovery.cancel()
        guard enabled, let session, let view = entries[session.viewID]?.view else { return }
        commandBackgroundAudio(view, frame: session.frame, document: session.document, token: session.token, action: action)
    }
    private func installRemoteCommands() {
        guard remoteTargets.isEmpty else { return }
        let commands = MPRemoteCommandCenter.shared()
        for (command, action) in [(commands.pauseCommand, "pause"), (commands.playCommand, "play")] {
            let target = command.addTarget { [weak self] _ in
                Task { @MainActor in self?.remote(action) }
                return .success
            }
            remoteTargets.append((command, target))
        }
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard let view = message.webView, let entry = entries[ObjectIdentifier(view)],
              let value = message.body as? [String: Any], let document = value["document"] as? String,
              document.count <= 64, let event = value["event"] as? String else { return }
        if event == "ready" {
            configureBackgroundAudio(view, frame: message.frameInfo, enabled: enabled && entry.tabID == selected, foreground: foreground)
        } else if event == "inventory", foreground {
            if entry.frames[document] == nil, entry.frames.count >= 64,
               let oldest = entry.frames.min(by: { $0.value.updated < $1.value.updated })?.key {
                entry.frames.removeValue(forKey: oldest)
            }
            entry.frames[document] = Frame(info: message.frameInfo, videos: Array((value["videos"] as? [[String: Any]] ?? []).prefix(32)), updated: ProcessInfo.processInfo.systemUptime)
        } else if let session, session.viewID == ObjectIdentifier(view), session.document == document,
                  value["token"] as? String == session.token {
            if event == "cancel" { recovery.cancel() }
            if event == "recover", enabled,
               recovery.consume(token: session.token, now: ProcessInfo.processInfo.systemUptime, background: !foreground && UIApplication.shared.applicationState != .active) {
                commandBackgroundAudio(view, frame: session.frame, document: document, token: session.token, action: "recover")
            }
        }
    }
}

@MainActor
private final class BackgroundAudioHandler: NSObject, WKScriptMessageHandler {
    weak var owner: BackgroundAudioController?
    init(owner: BackgroundAudioController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}
