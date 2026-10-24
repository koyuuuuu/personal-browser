import SwiftUI
import WebKit
import AVFoundation

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
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let id: UUID
    let isPrivate: Bool
    private var liveWebView: WKWebView?
    private var suppliedConfiguration: WKWebViewConfiguration?
    var webView: WKWebView {
        if let liveWebView { return liveWebView }
        return createWebView()
    }
    var existingWebView: WKWebView? { liveWebView }
    var isLive: Bool { liveWebView != nil }
    @Published var url: URL?
    @Published var title = "新しいタブ"
    @Published var progress = 0.0
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var hasContent = false
    @Published var errorMessage: String?
    @Published var dialog: JavaScriptDialog?
    @Published private(set) var hasActiveMedia = false
    @Published private(set) var isPictureInPicture = false
    @Published var previewData: Data?
    var preferences = FeaturePreferences()
    var swipeNavigation = true
    var onVisit: ((URL, String) -> Void)?
    var onStateChange: (() -> Void)?
    var onPopup: ((WKWebViewConfiguration, Bool) -> WKWebView?)?
    var onClose: (() -> Void)?
    var onExternalURL: ((URL) -> Void)?
    var onOpenLink: ((URL, Bool) -> Void)?
    var onShareLink: ((URL) -> Void)?
    var onAnalyzeLink: ((URL) -> Void)?
    var onMessageLink: ((URL) -> Void)?
    var onSaveLink: ((URL) -> Void)?
    var onOpenInBrowser: ((URL) -> Void)?
    var onDownload: ((URL) -> Void)?
    private var observations: [NSKeyValueObservation] = []
    private var mediaFrames: [String: Bool] = [:]
    private var pipFrames: [String: Bool] = [:]
    private var appliedRule: WKContentRuleList?
    private var pendingRequest: URL?
    private var snapshotInProgress = false
    private var downloads: [ObjectIdentifier: (WKDownload, URL?)] = [:]

    init(id: UUID = UUID(), isPrivate: Bool, configuration: WKWebViewConfiguration? = nil) {
        self.id = id; self.isPrivate = isPrivate; self.suppliedConfiguration = configuration
        super.init()
    }

    private func createWebView() -> WKWebView {
        let configuration = suppliedConfiguration ?? WKWebViewConfiguration()
        suppliedConfiguration = nil
        if configuration.websiteDataStore.isPersistent != !isPrivate {
            configuration.websiteDataStore = isPrivate ? .nonPersistent() : .default()
        }
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = preferences.enablePictureInPicture
        configuration.mediaTypesRequiringUserActionForPlayback = [.audio, .video]
        // A popup may share the parent's controller. Give each tab its own
        // message channel while preserving WebKit's process/opener/data store.
        configuration.userContentController = WKUserContentController()
        let handler = MediaMessageHandler(tab: self)
        configuration.userContentController.add(handler, name: "personalBrowserMedia")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.mediaScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let view = WKWebView(frame: .zero, configuration: configuration)
        liveWebView = view
        view.navigationDelegate = self; view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = swipeNavigation
        view.isFindInteractionEnabled = true
        observations = [
            view.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.progress = view.estimatedProgress }
            },
            view.observe(\.isLoading, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.isLoading = view.isLoading }
            },
            view.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoBack = view.canGoBack }
            },
            view.observe(\.canGoForward, options: [.initial, .new]) { [weak self] view, _ in
                Task { @MainActor in self?.canGoForward = view.canGoForward }
            },
            view.observe(\.url, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self, let url = view.url else { return }
                    self.url = url; self.onStateChange?()
                }
            },
            view.observe(\.title, options: [.new]) { [weak self] view, _ in
                Task { @MainActor in
                    guard let self, let title = view.title, !title.isEmpty else { return }
                    self.title = title; self.onStateChange?()
                }
            }
        ]
        if let target = pendingRequest ?? url {
            pendingRequest = nil
            Task { @MainActor [weak self, weak view] in
                guard let self, let view else { return }
                await self.configureBlocking(for: target, view: view)
                guard self.liveWebView === view else { return }
                view.load(URLRequest(url: target))
            }
        }
        return view
    }

    func applyPreferences(_ value: FeaturePreferences, swipe: Bool) {
        preferences = value; swipeNavigation = swipe
        liveWebView?.allowsBackForwardNavigationGestures = swipe
        if let view = liveWebView { Task { await self.configureBlocking(for: self.url, view: view) } }
    }

    private func configureBlocking(for url: URL?, view: WKWebView) async {
        guard preferences.shouldBlock(url) else {
            if let appliedRule { view.configuration.userContentController.remove(appliedRule); self.appliedRule = nil }
            return
        }
        guard appliedRule == nil else { return }
        let list = await ContentBlocking.shared.rules()
        guard liveWebView === view, preferences.shouldBlock(url), appliedRule == nil else { return }
        if let list { view.configuration.userContentController.add(list); appliedRule = list }
        else { errorMessage = "広告ブロックの準備に失敗しました。設定から再度有効にしてください。" }
    }

    func load(_ url: URL) {
        guard WebURLPolicy.allows(url) else { return }
        errorMessage = nil; hasContent = true; self.url = url
        if let view = liveWebView {
            Task { @MainActor [weak self, weak view] in
                guard let self, let view else { return }
                await self.configureBlocking(for: url, view: view)
                guard self.liveWebView === view else { return }
                view.load(URLRequest(url: url))
            }
        } else { pendingRequest = url }
        onStateChange?()
    }

    func capturePreview() {
        guard !snapshotInProgress, let view = liveWebView, hasContent, !hasActiveMedia else { return }
        snapshotInProgress = true
        let config = WKSnapshotConfiguration(); config.snapshotWidth = 240
        view.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self else { return }
            self.snapshotInProgress = false
            if let image { self.previewData = image.jpegData(compressionQuality: 0.45) }
        }
    }

    func suspend() {
        guard !hasActiveMedia, !isPictureInPicture, downloads.isEmpty else { return }
        releaseWebView(); isLoading = false; canGoBack = false; canGoForward = false
    }

    private func releaseWebView() {
        dialog?.resolve(nil); dialog = nil
        liveWebView?.stopLoading(); liveWebView?.navigationDelegate = nil; liveWebView?.uiDelegate = nil
        liveWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "personalBrowserMedia")
        observations.removeAll(); appliedRule = nil; liveWebView = nil
        mediaFrames.removeAll(); pipFrames.removeAll(); hasActiveMedia = false; isPictureInPicture = false
    }

    func updateMedia(_ payload: [String: Any]) {
        guard let frame = payload["frame"] as? String else { return }
        mediaFrames[frame] = payload["playing"] as? Bool ?? false
        hasActiveMedia = mediaFrames.values.contains(true)
        if hasActiveMedia {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        pipFrames[frame] = payload["pip"] as? Bool ?? false
        isPictureInPicture = pipFrames.values.contains(true)
        onStateChange?()
    }

    private static let mediaScript = """
    (() => {
      const frame = Math.random().toString(36).slice(2), players = new Set();
      const report = () => {
        let playing = false, pip = false;
        players.forEach(v => { if (!v.isConnected) players.delete(v); else {
          playing ||= !v.paused && !v.ended;
          pip ||= v.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === v;
        }});
        window.webkit.messageHandlers.personalBrowserMedia.postMessage({frame,playing:playing||pip,pip});
      };
      const scan = () => { document.querySelectorAll('video,audio').forEach(v => {
        if (players.has(v)) return; players.add(v);
        ['play','playing','pause','ended','enterpictureinpicture','leavepictureinpicture','webkitpresentationmodechanged'].forEach(e => v.addEventListener(e,report));
      }); report(); };
      document.addEventListener('DOMContentLoaded', () => { scan(); new MutationObserver(scan).observe(document.documentElement,{childList:true,subtree:true}); });
      window.addEventListener('pagehide', () => window.webkit.messageHandlers.personalBrowserMedia.postMessage({frame,playing:false,pip:false}));
    })();
    """

    func loadTestFixture() {
        hasContent = true
        let view = webView
        url = URL(string: "https://fixture.invalid")
        view.stopLoading()
        view.loadHTMLString("""
        <!doctype html><meta name="viewport" content="width=device-width,initial-scale=1">
        <title>テストページ</title><h1>オフラインのテストページ</h1>
        <p>ネット接続を使わずにWebKit表示を確認します。</p>
        <button onclick="document.getElementById('result').textContent='操作成功'">ページ内ボタン</button>
        <p id="result"></p>
        """, baseURL: URL(string: "https://fixture.invalid"))
    }

    func dispose() {
        for (_, item) in downloads {
            item.0.cancel { _ in }
            if let target = item.1 { try? FileManager.default.removeItem(at: target) }
        }
        downloads.removeAll(); releaseWebView()
        onVisit = nil; onStateChange = nil; onPopup = nil; onClose = nil; onExternalURL = nil
        onAnalyzeLink = nil; onMessageLink = nil; onSaveLink = nil; onOpenLink = nil; onShareLink = nil; onOpenInBrowser = nil; onDownload = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url {
            self.url = url
            onVisit?(url, webView.title ?? url.host ?? "ページ")
        }
        capturePreview()
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
                decisionHandler(.download)
            } else {
                if navigationAction.targetFrame?.isMainFrame == true {
                    Task { @MainActor in
                        await self.configureBlocking(for: url, view: webView)
                        decisionHandler(.allow)
                    }
                } else { decisionHandler(.allow) }
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
            decisionHandler(.download)
        }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil, preferences.allowPopups else { return nil }
        // Use WebKit's supplied configuration so window.opener/authentication state is retained.
        return onPopup?(configuration, isPrivate)
    }

    func webViewDidClose(_ webView: WKWebView) { onClose?() }

    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
        guard let link = elementInfo.linkURL, WebURLPolicy.allows(link) else { completionHandler(nil); return }
        let menu = UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            let applications = ExternalApplication.allCases.filter { self.preferences.externalApplications.contains($0.rawValue) }.map { app in
                UIAction(title: app.label, image: UIImage(systemName: "arrow.up.forward.app")) { [weak self] _ in
                    guard let destination = app.destination(for: link) else { return }
                    UIApplication.shared.open(destination) { opened in
                        if !opened { Task { @MainActor in self?.errorMessage = "このアプリを開けませんでした。共有から別のアプリを選べます。" } }
                    }
                }
            }
            let related = UIAction(title: "対応するアプリ", image: UIImage(systemName: "app")) { [weak self] _ in
                UIApplication.shared.open(link, options: [.universalLinksOnly: true]) { opened in
                    if !opened { Task { @MainActor in self?.errorMessage = "このリンクに対応するアプリが見つかりません。" } }
                }
            }
            var appActions: [UIMenuElement] = []
            if WatchHTML.youtubeURL(link) != nil {
                appActions.append(UIAction(title: "YouTube", image: UIImage(systemName: "play.rectangle")) { [weak self] _ in
                    UIApplication.shared.open(link, options: [.universalLinksOnly: true]) { opened in
                        if !opened { Task { @MainActor in self?.errorMessage = "YouTubeアプリを開けませんでした。ブラウザで開くこともできます。" } }
                    }
                })
            }
            appActions += [related]
            appActions += applications
            appActions += [
                UIAction(title: "Safari / 既定のブラウザ", image: UIImage(systemName: "safari")) { [weak self] _ in self?.onOpenInBrowser?(link) },
                UIAction(title: "ファイルにリンクを保存", image: UIImage(systemName: "folder")) { [weak self] _ in self?.onSaveLink?(link) },
                UIAction(title: "メール", image: UIImage(systemName: "envelope")) { _ in
                    var parts = URLComponents(); parts.scheme = "mailto"; parts.queryItems = [URLQueryItem(name: "body", value: link.absoluteString)]
                    if let url = parts.url { UIApplication.shared.open(url) }
                },
                UIAction(title: "メッセージ", image: UIImage(systemName: "message")) { [weak self] _ in self?.onMessageLink?(link) }
            ]
            for name in ["メモ", "ChatGPT", "Claude", "その他のアプリ"] {
                appActions.append(UIAction(title: name + "（共有から選択）", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.onShareLink?(link) })
            }
            return UIMenu(children: [
                UIAction(title: "このタブで開く", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in self?.load(link) },
                UIAction(title: "新しいタブで開く", image: UIImage(systemName: "plus.square")) { [weak self] _ in self?.onOpenLink?(link, self?.isPrivate ?? false) },
                UIAction(title: "リンクをコピー", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.url = link },
                UIAction(title: "共有", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.onShareLink?(link) },
                UIAction(title: "Watch HTMLで解析", image: UIImage(systemName: "play.rectangle.on.rectangle")) { [weak self] _ in self?.onAnalyzeLink?(link) },
                UIMenu(title: "アプリで開く", image: UIImage(systemName: "arrow.up.forward.app"), children: appActions)
            ])
        }
        completionHandler(menu)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { begin(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { begin(download) }
    private func begin(_ download: WKDownload) {
        guard !isPrivate else {
            errorMessage = "プライベートタブのファイルは端末に残さない設定です。通常タブでダウンロードしてください。"
            download.cancel { _ in }; return
        }
        downloads[ObjectIdentifier(download)] = (download, nil); download.delegate = self
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Downloads", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let name = URL(fileURLWithPath: suggestedFilename).lastPathComponent
            let target = folder.appendingPathComponent(String(UUID().uuidString.prefix(8)) + "-" + (name.isEmpty ? "download" : name))
            downloads[ObjectIdentifier(download)] = (download, target)
            completionHandler(target)
        } catch { errorMessage = "保存先を作成できませんでした。"; completionHandler(nil) }
    }
    func downloadDidFinish(_ download: WKDownload) {
        if let item = downloads.removeValue(forKey: ObjectIdentifier(download)), let target = item.1 {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: target.path)
            onDownload?(target)
        }
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let item = downloads.removeValue(forKey: ObjectIdentifier(download)), let target = item.1 { try? FileManager.default.removeItem(at: target) }
        errorMessage = "ダウンロードできませんでした。接続と空き容量を確認してください。"
    }

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

@MainActor
private final class MediaMessageHandler: NSObject, WKScriptMessageHandler {
    weak var tab: BrowserTab?
    init(tab: BrowserTab) { self.tab = tab }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if let value = message.body as? [String: Any] { tab?.updateMedia(value) }
    }
}

/// The surface stays mounted while chrome, tabs, home, and scene phase change.
/// Media WebViews remain attached to the window so PiP keeps its render surface.
struct WebSurface: UIViewRepresentable {
    @ObservedObject var store: BrowserStore
    func makeUIView(context: Context) -> WebSurfaceView { WebSurfaceView() }
    func updateUIView(_ host: WebSurfaceView, context: Context) {
        guard let selected = store.selectedTab else { return }
        let kept = store.tabs.filter { $0.id == selected.id || $0.hasActiveMedia || $0.isPictureInPicture }
        let views = kept.compactMap { $0.id == selected.id && $0.hasContent ? $0.webView : $0.existingWebView }
        for view in host.subviews where !views.contains(where: { $0 === view }) { view.removeFromSuperview() }
        for tab in kept {
            guard let view = tab.existingWebView else { continue }
            if view.superview !== host { host.addSubview(view) }
            view.isUserInteractionEnabled = tab.id == selected.id && tab.hasContent
            // Do not hide a playing WebView or detach it on backgrounding.
            view.alpha = tab.id == selected.id && tab.hasContent ? 1 : 0.01
        }
        if let view = selected.existingWebView { host.bringSubviewToFront(view) }
        host.setNeedsLayout()
    }
}
final class WebSurfaceView: UIView {
    override func layoutSubviews() { super.layoutSubviews(); for view in subviews { view.frame = bounds } }
}
