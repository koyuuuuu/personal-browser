import WebKit

/// Only a one-way boolean for trusted edits; never reads field values.
@MainActor
final class PageEditObserver: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    init(tab: BrowserTab) { self.tab = tab }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.body as? [String: Bool])?["edited"] == true { tab?.markEditedInput() }
    }
    static let source = #"""
    (() => {
      let reported = false;
      const changed = event => {
        const element = event.target;
        if (reported || !event.isTrusted || !(element instanceof Element) ||
            !element.matches('input,textarea,select,[contenteditable="true"]')) return;
        reported = true;
        webkit.messageHandlers.browserPageEdited.postMessage({edited:true});
      };
      document.addEventListener('input', changed, true);
      document.addEventListener('change', changed, true);
    })();
    """#
}
