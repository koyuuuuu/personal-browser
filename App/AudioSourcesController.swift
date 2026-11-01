import Combine
import WebKit

struct BrowserAudioSource: Identifiable, Equatable {
    let tabID: UUID
    let frameID: String
    let sourceID: String
    let kind: String
    let label: String
    let playing: Bool
    let muted: Bool
    let volume: Double
    let actualVolume: Double
    let mode: String
    let reason: String
    var id: String { tabID.uuidString + "/" + frameID + "/" + sourceID }
}

/// Ephemeral, per-document media inventory. It never instantiates a WebView,
/// records source URLs, or writes private/normal playback data to disk.
@MainActor
final class AudioSourcesController: ObservableObject {
    static let shared = AudioSourcesController()
    @Published private(set) var sources: [BrowserAudioSource] = []
    private var entries: [ObjectIdentifier: Entry] = [:]
    private final class Entry {
        weak var view: WKWebView?
        let tabID: UUID
        var frames: [String: WKFrameInfo] = [:]
        var values: [String: [BrowserAudioSource]] = [:]
        init(_ view: WKWebView, tabID: UUID) { self.view = view; self.tabID = tabID }
    }

    func attach(_ view: WKWebView, tabID: UUID) {
        entries[ObjectIdentifier(view)] = Entry(view, tabID: tabID)
        let controller = view.configuration.userContentController
        controller.add(AudioSourcesMessageHandler(owner: self), contentWorld: .defaultClient, name: "browserAudioSources")
        controller.addUserScript(WKUserScript(source: MediaVolumeScript.source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
    }
    func detach(_ view: WKWebView) {
        entries.removeValue(forKey: ObjectIdentifier(view))
        view.configuration.userContentController.removeScriptMessageHandler(forName: "browserAudioSources", contentWorld: .defaultClient)
        publish()
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard let view = message.webView, let entry = entries[ObjectIdentifier(view)], entry.view === view,
              let body = message.body as? [String: Any], let frame = body["frame"] as? String,
              !frame.isEmpty, frame.utf8.count <= 128 else { return }
        if body["ready"] as? Bool == true && message.frameInfo.isMainFrame {
            entry.frames.removeAll(); entry.values.removeAll()
        }
        if body["gone"] as? Bool == true {
            entry.frames.removeValue(forKey: frame); entry.values.removeValue(forKey: frame); publish(); return
        }
        guard entry.frames[frame] != nil || entry.frames.count < 64 else { return }
        entry.frames[frame] = message.frameInfo
        guard let values = body["sources"] as? [[String: Any]] else { return }
        var seen = Set<String>()
        entry.values[frame] = values.prefix(64).compactMap { value in
            guard let id = value["id"] as? String, id.count <= 64, seen.insert(id).inserted,
                  let kind = value["kind"] as? String, ["audio", "video"].contains(kind),
                  let mode = value["mode"] as? String, ["candidate", "unsupported", "busy", "gain"].contains(mode),
                  let playing = value["playing"] as? Bool, let muted = value["muted"] as? Bool,
                  let volume = value["volume"] as? Double, volume.isFinite,
                  let actual = value["actualVolume"] as? Double, actual.isFinite else { return nil }
            return BrowserAudioSource(tabID: entry.tabID, frameID: frame, sourceID: id, kind: kind,
                label: String((value["label"] as? String ?? "").prefix(100)), playing: playing, muted: muted,
                volume: min(1, max(0, volume)), actualVolume: min(1, max(0, actual)),
                mode: mode, reason: String((value["reason"] as? String ?? "").prefix(240)))
        }
        publish()
    }
    private func publish() {
        let values = entries.values.flatMap { $0.values.values.flatMap { $0 } }.sorted { $0.id < $1.id }
        if sources != values { sources = values }
    }
    private func command(_ source: BrowserAudioSource, action: String, value: Any? = nil) {
        guard let entry = entries.values.first(where: { $0.tabID == source.tabID }), let view = entry.view,
              let frame = entry.frames[source.frameID],
              entry.values[source.frameID]?.contains(where: { $0.id == source.id }) == true else { return }
        var payload: [String: Any] = ["frame": source.frameID, "source": source.sourceID, "action": action]
        if let value { payload["value"] = value }
        guard let data = try? JSONSerialization.data(withJSONObject: payload), let json = String(data: data, encoding: .utf8) else { return }
        runAudioMixerCommand(view, frame: frame, json: json)
    }
    func setMuted(_ source: BrowserAudioSource, _ value: Bool) { command(source, action: "mute", value: value) }
    func setVolume(_ source: BrowserAudioSource, _ value: Double) {
        guard value.isFinite, source.mode == "gain" else { return }
        command(source, action: "gain", value: min(1, max(0, value)))
    }
    func enable(_ source: BrowserAudioSource) { command(source, action: "enable") }
}

@MainActor
private final class AudioSourcesMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: AudioSourcesController?
    init(owner: AudioSourcesController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}
