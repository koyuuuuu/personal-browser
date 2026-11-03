import Combine
import WebKit

/// Original, bounded DOM compatibility logic; no downloaded executable code.
/// Independent of network-ad filtering, with the existing site exclusions.
@MainActor
final class AppPromotionBlocker: ObservableObject {
    static let shared = AppPromotionBlocker()
    @Published private(set) var enabled: Bool = UserDefaults.standard.object(forKey: "browser.appPromotions.block.v1") as? Bool ?? true
    private var entries: [ObjectIdentifier: Entry] = [:]
    private final class Entry {
        weak var view: WKWebView?
        var excluded: [String]
        var documentURL: URL?
        let lock: (Bool) -> Void
        init(_ view: WKWebView, excluded: [String], lock: @escaping (Bool) -> Void) { self.view = view; self.excluded = excluded; self.lock = lock }
    }
    func setEnabled(_ value: Bool) {
        enabled = value; UserDefaults.standard.set(value, forKey: "browser.appPromotions.block.v1")
        for entry in entries.values { apply(entry) }
    }
    func attach(_ view: WKWebView, excluded: [String], lock: @escaping (Bool) -> Void) {
        entries[ObjectIdentifier(view)] = Entry(view, excluded: excluded, lock: lock)
        let controller = view.configuration.userContentController
        controller.add(PromotionMessageHandler(owner: self), contentWorld: .defaultClient, name: "browserAppPromotions")
        var test = false
        #if DEBUG
        test = ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-resilience-fixture")
        #endif
        let source = AppPromotionScript.source.replacingOccurrences(of: "__PB_TEST_REDDIT__", with: test ? "(location.origin === 'http://127.0.0.1:18765' && location.pathname === '/app-promotion-fixture')" : "false")
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
    }
    func update(_ view: WKWebView, excluded: [String]) {
        guard let entry = entries[ObjectIdentifier(view)] else { return }
        entry.excluded = excluded; apply(entry)
    }
    func detach(_ view: WKWebView) {
        entries.removeValue(forKey: ObjectIdentifier(view))
        view.configuration.userContentController.removeScriptMessageHandler(forName: "browserAppPromotions", contentWorld: .defaultClient)
    }
    fileprivate func receive(_ message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let view = message.webView,
              let entry = entries[ObjectIdentifier(view)] else { return }
        if message.body as? String == "ready" {
            entry.documentURL = message.frameInfo.request.url
            apply(entry)
        } else if let locked = message.body as? Bool { entry.lock(locked) }
    }
    private func apply(_ entry: Entry) {
        guard let view = entry.view else { return }
        let host = (entry.documentURL ?? view.url)?.host?.lowercased() ?? ""
        let allowed = enabled && !entry.excluded.contains { host == $0 || host.hasSuffix("." + $0) }
        applyAppPromotionPolicy(view, enabled: allowed)
    }
}

@MainActor
private final class PromotionMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: AppPromotionBlocker?
    init(owner: AppPromotionBlocker) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) { owner?.receive(message) }
}
