import AVFoundation
import Combine
import WebKit
import UIKit
#if DEBUG
import SwiftUI
#endif

/// Playback ignores the Ring/Silent switch in every preference combination.
/// Mixing stays best effort; no pause/play retries or session deactivation.
@MainActor
final class AudioMixingController: ObservableObject {
    static let shared = AudioMixingController()
    private let defaults: UserDefaults
    private static let enabledKey = "browser.audioMixing.enabled.v1"
    private static let webKey = "browser.audioMixing.nonExclusiveWeb.v1"
    @Published private(set) var enabled: Bool
    @Published private(set) var nonExclusiveWebAudio: Bool
    @Published private(set) var errorMessage: String?
    private var timer: Timer?
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var activeObservation: AnyCancellable?
    #if DEBUG
    @Published private(set) var fixtureStatus = "Audio policy waiting"
    private var fixtureReturns = 0
    static var fixture: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--ui-testing") && args.contains("--ui-playback-audio-fixture")
    }
    #endif

    private final class Entry {
        weak var view: WKWebView?
        let playback: (Bool) -> Void
        init(_ view: WKWebView, playback: @escaping (Bool) -> Void) { self.view = view; self.playback = playback }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        nonExclusiveWebAudio = defaults.object(forKey: Self.webKey) as? Bool ?? true
        activeObservation = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.returned() }
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; defaults.set(value, forKey: Self.enabledKey); errorMessage = nil
        updateViews()
    }
    func setNonExclusiveWebAudio(_ value: Bool) {
        guard nonExclusiveWebAudio != value else { return }
        nonExclusiveWebAudio = value; defaults.set(value, forKey: Self.webKey)
        updateViews()
    }

    func attach(_ view: WKWebView, playback: @escaping (Bool) -> Void) {
        entries[ObjectIdentifier(view)] = Entry(view, playback: playback)
        let controller = view.configuration.userContentController
        controller.add(MixingMessageHandler(owner: self, view: view), contentWorld: .defaultClient, name: "browserAudioMixing")
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
        prepare(activate: false)
        if enabled { startTimer(); sample(view) }
    }
    func detach(_ view: WKWebView) {
        entries.removeValue(forKey: ObjectIdentifier(view))?.playback(false)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "browserAudioMixing", contentWorld: .defaultClient)
        if entries.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func updateViews() {
        prepare(activate: false)
        if enabled { startTimer() }
        else { timer?.invalidate(); timer = nil }
        for entry in entries.values {
            guard let view = entry.view else { continue }
            applyWebPolicy(view)
            if enabled { sample(view) } else { entry.playback(false) }
        }
    }
    fileprivate func applyWebPolicy(_ view: WKWebView) {
        guard entries[ObjectIdentifier(view)] != nil else { return }
        applyAudioMixingPolicy(view, enabled: enabled && nonExclusiveWebAudio)
    }
    private func returned() {
        // Control Center makes the app inactive without navigating. Reassert
        // playback on return, without resuming or activating stopped media.
        guard !entries.isEmpty else { return }
        #if DEBUG
        if Self.fixture { fixtureReturns += 1 }
        #endif
        prepare(activate: false)
        for entry in entries.values { if let view = entry.view { applyWebPolicy(view) } }
    }
    fileprivate func mediaEvent(_ view: WKWebView, audible: Bool) {
        guard entries[ObjectIdentifier(view)] != nil else { return }
        if audible { prepare(activate: true) }
        if enabled { sample(view) }
    }
    fileprivate func policyEvent(_ view: WKWebView, type: String) {
        guard entries[ObjectIdentifier(view)] != nil else { return }
        #if DEBUG
        if Self.fixture {
            let session = AVAudioSession.sharedInstance()
            fixtureStatus = "Native \(session.category == .playback ? "playback" : "other"); Web \(type == "playback" ? "playback" : "other"); mix\(session.categoryOptions.contains(.mixWithOthers)); return\(fixtureReturns)"
        }
        #endif
    }
    private func prepare(activate: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            guard session.category != .record && session.category != .playAndRecord else {
                errorMessage = "録音・通話用の音声セッションを優先しています。終了後に同時再生を試してください。"
                return
            }
            if session.category != .playback || session.mode != .moviePlayback || !session.categoryOptions.contains(.mixWithOthers) {
                try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            }
            if activate { try session.setActive(true) }
            errorMessage = nil
        } catch { errorMessage = "音声ミックスの設定を適用できませんでした。再生を止めて設定を入れ直してください。" }
    }
    private func startTimer() {
        guard timer == nil, !entries.isEmpty else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                for entry in self.entries.values { if let view = entry.view { self.sample(view) } }
            }
        }
    }
    private func sample(_ view: WKWebView) {
        guard let entry = entries[ObjectIdentifier(view)] else { return }
        view.requestMediaPlaybackState { [weak self, weak entry] state in
            guard let self, let entry, let view = entry.view,
                  self.entries[ObjectIdentifier(view)] === entry else { return }
            entry.playback(self.enabled && state == .playing)
        }
    }

    static let script =
        #"""
        (() => {
          if (globalThis.__personalBrowserSetAudioMixing) return;
          const send = value => { try { webkit.messageHandlers.browserAudioMixing.postMessage(value); } catch (_) {} };
          const apply = () => {
            // ambient is mixable but obeys the hardware Silent switch. The
            // user's playback requirement takes priority for BOTH settings.
            // Native playback+mixWithOthers still requests supported mixing.
            // AudioSession belongs to the current document. Embedded players
            // need their own policy too, including cross-origin frames.
            if (!navigator.audioSession) return;
            try {
              const session = navigator.audioSession;
              if (session.type === 'play-and-record') return;
              if (session.type !== 'playback') session.type = 'playback';
              send({type:session.type});
            } catch (_) { /* Permissions Policy / API support is site-dependent. */ }
          };
          globalThis.__personalBrowserSetAudioMixing = apply;
          const ready = () => { apply(); if (window === window.top) send('ready'); };
          ready(); window.addEventListener('pageshow', ready);
          document.addEventListener('visibilitychange', () => { if (!document.hidden) ready(); });
          document.addEventListener('play', event => {
            apply();
            const player = event.target;
            const audible = player instanceof HTMLMediaElement && !player.muted && player.volume > 0;
            send(audible);
          }, true);
          if (navigator.audioSession) navigator.audioSession.addEventListener('statechange', apply);
        })();
        """#
}

@MainActor
private final class MixingMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: AudioMixingController?
    weak var view: WKWebView?
    init(owner: AudioMixingController, view: WKWebView) { self.owner = owner; self.view = view }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view, message.webView === view else { return }
        if message.body as? String == "ready" { owner?.applyWebPolicy(view) }
        else if let audible = message.body as? Bool { owner?.mediaEvent(view, audible: audible) }
        else if let value = message.body as? [String: Any], let type = value["type"] as? String { owner?.policyEvent(view, type: type) }
    }
}

#if DEBUG
@MainActor
struct PlaybackAudioFixtureStatus: View {
    @ObservedObject private var controller = AudioMixingController.shared
    var body: some View {
        Text(controller.fixtureStatus).font(.system(size: 9)).frame(width: 185)
            .background(.background).accessibilityIdentifier("playbackAudioStatus").allowsHitTesting(false)
    }
}
#endif
