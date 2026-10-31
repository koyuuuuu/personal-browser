import AVFoundation
import Combine
import WebKit

/// Opt-in additions to the existing build14 playback path. No pause/play retry
/// loops, private WebKit preferences, or audio-session deactivation on toggle.
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
    private var usesWebMixing: Bool { enabled && nonExclusiveWebAudio }

    private final class Entry {
        weak var view: WKWebView?
        let playback: (Bool) -> Void
        init(_ view: WKWebView, playback: @escaping (Bool) -> Void) { self.view = view; self.playback = playback }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: Self.enabledKey)
        nonExclusiveWebAudio = defaults.object(forKey: Self.webKey) as? Bool ?? true
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
        if enabled { prepare(activate: false); startTimer(); sample(view) }
    }
    func detach(_ view: WKWebView) {
        entries.removeValue(forKey: ObjectIdentifier(view))?.playback(false)
        view.configuration.userContentController.removeScriptMessageHandler(forName: "browserAudioMixing", contentWorld: .defaultClient)
        if entries.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func updateViews() {
        if enabled { prepare(activate: false); startTimer() }
        else { timer?.invalidate(); timer = nil }
        for entry in entries.values {
            guard let view = entry.view else { continue }
            applyWebPolicy(view)
            if enabled { sample(view) } else { entry.playback(false) }
        }
    }
    fileprivate func applyWebPolicy(_ view: WKWebView) {
        guard entries[ObjectIdentifier(view)] != nil else { return }
        applyAudioMixingPolicy(view, enabled: usesWebMixing)
    }
    fileprivate func mediaEvent(_ view: WKWebView, audible: Bool) {
        guard enabled, entries[ObjectIdentifier(view)] != nil else { return }
        if audible { prepare(activate: true) }
        sample(view)
    }
    private func prepare(activate: Bool) {
        do {
            let session = AVAudioSession.sharedInstance()
            guard session.category != .record && session.category != .playAndRecord else {
                errorMessage = "録音・通話用の音声セッションを優先しています。終了後に同時再生を試してください。"
                return
            }
            try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
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

    private static let script =
        """
        (() => {
          let enabled = false, previous = null;
          const apply = value => {
            enabled = value;
            // AudioSession type is page-wide. Only the top document owns the
            // override, so sibling/cross-origin frames cannot restore it twice.
            if (window !== window.top || !navigator.audioSession) return;
            try {
              const session = navigator.audioSession;
              if (enabled) {
                if (session.type === 'play-and-record') return;
                if (previous === null) previous = session.type;
                if (session.type !== 'ambient') session.type = 'ambient';
              } else if (previous !== null) {
                if (session.type === 'ambient') session.type = previous;
                previous = null;
              }
            } catch (_) { /* Permissions Policy / API support is site-dependent. */ }
          };
          globalThis.__personalBrowserSetAudioMixing = apply;
          // Fetch current preferences on every document/BFCache presentation;
          // a setting captured at WebView creation would become stale on reload.
          const ready = () => { if (window === window.top) window.webkit.messageHandlers.browserAudioMixing.postMessage('ready'); };
          ready(); window.addEventListener('pageshow', ready);
          document.addEventListener('play', event => {
            apply(enabled);
            const player = event.target;
            const audible = player instanceof HTMLMediaElement && !player.muted && player.volume > 0;
            window.webkit.messageHandlers.browserAudioMixing.postMessage(audible);
          }, true);
          if (navigator.audioSession) navigator.audioSession.addEventListener('statechange', () => {
            window.webkit.messageHandlers.browserAudioMixing.postMessage(false);
          });
        })();
        """
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
    }
}
