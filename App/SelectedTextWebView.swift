import UIKit
import WebKit

/// Public responder-chain menu customization; WebKit may omit it in some
/// selection contexts, so the browser also exposes a selected-text overlay.
@MainActor
final class SelectedTextWebView: WKWebView {
    var onSelection: ((String) -> Void)?
    var onSearch: ((String) -> Void)?
    private(set) var selection = ""

    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        let controller = self.configuration.userContentController
        controller.add(SelectionHandler(view: self), contentWorld: .defaultClient, name: "browserSelection")
        controller.addUserScript(WKUserScript(source: Self.selectionScript, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .defaultClient))
    }
    required init?(coder: NSCoder) { fatalError("Use the configured initializer") }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard !selection.isEmpty else { return }
        let text = selection
        let action = UIAction(title: "自作ブラウザで検索", image: UIImage(systemName: "magnifyingglass")) { [weak self] _ in self?.onSearch?(text) }
        // Append only: keep Copy, Share, Look Up and WebKit's other actions.
        builder.insertChild(UIMenu(title: "", options: .displayInline, children: [action]), atEndOfMenu: .root)
    }

    func clearSelection() { updateSelection("") }
    fileprivate func updateSelection(_ text: String) {
        guard selection != text else { return }
        selection = text; onSelection?(text)
    }

    private static let selectionScript = """
    (() => {
      function update() {
        let text = '';
        const field = document.activeElement;
        // Never read passwords. Read editable text only while it has focus.
        if (field && field.tagName === 'INPUT' && field.type === 'password') {
          text = '';
        } else if (field && (field.tagName === 'TEXTAREA' ||
                   (field.tagName === 'INPUT' && ['text','search','url','tel'].includes(field.type)))) {
          if (field.selectionStart !== null) text = field.value.substring(field.selectionStart, field.selectionEnd);
        } else {
          text = String(window.getSelection() || '');
        }
        // Oversized selections stay oversized for native validation; never
        // silently search a truncated phrase. This bounds bridge allocation.
        window.webkit.messageHandlers.browserSelection.postMessage(text.trim().slice(0, 16385));
      }
      document.addEventListener('selectionchange', update);
      document.addEventListener('select', update);
    })();
    """
}

@MainActor
private final class SelectionHandler: NSObject, WKScriptMessageHandler {
    weak var view: SelectedTextWebView?
    init(view: SelectedTextWebView) { self.view = view }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.webView === view, let text = message.body as? String else { return }
        view?.updateSelection(text)
    }
}
