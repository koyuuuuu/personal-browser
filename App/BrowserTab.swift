import SwiftUI
import WebKit

@MainActor
final class JavaScriptDialog: Identifiable {
    enum Kind { case alert, confirm, prompt }
    let id = UUID()
    let kind: Kind
    let message: String
    let defaultText: String
    private var completion: ((String?) -> Void)?

    init(kind: Kind, message: String, defaultText: String = "", completion: @escaping (String?) -> Void) {
        self.kind = kind
        self.message = message
        self.defaultText = defaultText
        self.completion = completion
    }

    func resolve(_ value: String?) {
        let callback = completion
        completion = nil
        callback?(value)
    }
}

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id: UUID
    let isPrivate: Bool
    let webView: WKWebView
    @Published var url: URL?
    @Published var title = "新しいタブ"
    @Published var progress = 0.0
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var hasContent = false
    @Published var errorMessage: String?
    @Published var dialog: JavaScriptDialog?

    var onVisit: ((URL, String) -> Void)?
    var onStateChange: (() -> Void)?
    var onPopup: ((WKWebViewConfiguration, Bool) -> WKWebView?)?
    var onClose: (() -> Void)?
    var onExternalURL: ((URL) -> Void)?
    private var observations: [NSKeyValueObservation] = []

    init(id: UUID = UUID(), isPrivate: Bool, configuration: WKWebViewConfiguration? = nil) {
        self.id = id
        self.isPrivate = isPrivate
        let configuration = configuration ?? {
            let value = WKWebViewConfiguration()
            value.websiteDataStore = isPrivate ? .nonPersistent() : .default()
            value.allowsInlineMediaPlayback = true
            return value
        }()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
            webView.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self, let url = view.url else { return }
                    self.url = url
                    self.onStateChange?()
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self, let title = view.title, !title.isEmpty else { return }
                    self.title = title
                    self.onStateChange?()
                }
            }
        ]
    }

    func load(_ url: URL) {
        guard WebURLPolicy.allows(url) else { return }
        errorMessage = nil
        hasContent = true
        self.url = url
        webView.load(URLRequest(url: url))
        onStateChange?()
    }

    func loadTestFixture() {
        hasContent = true
        webView.loadHTMLString("""
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>テストページ</title><h1>オフラインのテストページ</h1>
        <p>ネット接続を使わずにWebKit表示を確認します。</p>
        <button onclick="document.getElementById('result').textContent='操作成功'">ページ内ボタン</button>
        <p id="result"></p>
        """, baseURL: URL(string: "https://fixture.invalid"))
    }

    func dispose() {
        dialog?.resolve(nil)
        dialog = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observations.removeAll()
        onVisit = nil
        onStateChange = nil
        onPopup = nil
        onClose = nil
        onExternalURL = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url {
            self.url = url
            onVisit?(url, webView.title ?? url.host ?? "ページ")
        }
        onStateChange?()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    private func show(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        errorMessage = "ページの表示処理が終了しました。再読み込みしてください。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "about", "blob", "data"].contains(scheme) {
            if navigationAction.shouldPerformDownload {
                errorMessage = "この版ではファイルのダウンロード保存に対応していません。"
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        } else {
            decisionHandler(.cancel)
            if ["mailto", "tel", "sms", "itms-apps"].contains(scheme),
               navigationAction.targetFrame?.isMainFrame != false {
                onExternalURL?(url)
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            errorMessage = "この形式のファイルは、現在の版では保存できません。"
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        // Use WebKit's supplied configuration so window.opener/authentication state is retained.
        return onPopup?(configuration, isPrivate)
    }

    func webViewDidClose(_ webView: WKWebView) { onClose?() }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        dialog?.resolve(nil)
        dialog = JavaScriptDialog(kind: .alert, message: message) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        dialog?.resolve(nil)
        dialog = JavaScriptDialog(kind: .confirm, message: message) { completionHandler($0 != nil) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        dialog?.resolve(nil)
        dialog = JavaScriptDialog(kind: .prompt, message: prompt, defaultText: defaultText ?? "", completion: completionHandler)
    }
}

struct WebViewHost: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
