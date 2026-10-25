import SwiftUI
import WebKit
import AVFoundation
import Security
import CryptoKit

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
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, UIScrollViewDelegate {
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
    var isCapturingPreview: Bool { snapshotInProgress }
    var isProtectedForMedia: Bool { hasActiveMedia || isPictureInPicture }
    private var previousScrollY: CGFloat?
    var onConnectionRequest: ((ConnectionRequest) -> Void)?
    var trustsCertificate: ((String, String) -> Bool)?
    var rememberCertificate: ((String, String) -> Void)?
    var rememberHTTP: ((URL) -> Void)?
    private var pendingConnection: ConnectionRequest?
    private var navigationGrants: [String: String] = [:]
    private var certificateWarningShown = false
    private var pageZoom = 1.0
    var onVerticalScroll: ((CGFloat) -> Void)?
    var onRevealChrome: (() -> Void)?
    var onPreview: ((Data, URL, String) -> Void)?
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
    @Published var previewData: Data? { didSet { previewGeneration = UUID() } }
    private(set) var previewGeneration = UUID()
    var preferences = FeaturePreferences()
    var swipeNavigation = true
    var onVisit: ((URL, String) -> Void)?
    var onStateChange: (() -> Void)?
    var onPopup: ((WKWebViewConfiguration, Bool) -> WKWebView?)?
    var onClose: (() -> Void)?
    var onExternalURL: ((URL) -> Void)?
    var prefersApplication: ((URL) -> Bool)?
    var onPreferBrowser: ((URL) -> Void)?
    var onPreferApplication: ((URL) -> Void)?
    private var lastTopLevelRequest: URLRequest?
    private var expectedInterruptions: [URL: Date] = [:]
    private var retriedInterruptedURLs = Set<URL>()
    var onOpenLink: ((URL, Bool) -> Void)?
    var onShareLink: ((URL) -> Void)?
    var onAnalyzeLink: ((URL) -> Void)?
    var onMessageLink: ((URL) -> Void)?
    var onSaveLink: ((URL) -> Void)?
    var onOpenInBrowser: ((URL) -> Void)?
    var onOpenInSafari: ((URL) -> Void)?
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
        let os = ProcessInfo.processInfo.operatingSystemVersion
        configuration.applicationNameForUserAgent = "Version/\(os.majorVersion).\(os.minorVersion) Mobile/15E148 Safari/604.1"
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
        view.scrollView.delegate = self
        view.pageZoom = pageZoom
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

    func applyPresentation(_ value: PresentationPreferences) {
        if pageZoom != value.pageZoom { pageZoom = value.pageZoom; liveWebView?.pageZoom = pageZoom }
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
        pendingConnection?.resolve(allow: false); pendingConnection = nil; navigationGrants = [:]; certificateWarningShown = false
        retriedInterruptedURLs.removeAll()
        lastTopLevelRequest = URLRequest(url: url)
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
        guard !snapshotInProgress, let view = liveWebView, hasContent, !hasActiveMedia, !isPictureInPicture,
              UIApplication.shared.applicationState == .active, view.window != nil, view.alpha == 1,
              let capturedURL = url, WebURLPolicy.allows(capturedURL), view.bounds.width > 1, view.bounds.height > 1 else { return }
        snapshotInProgress = true
        let capturedTitle = title
        let config = WKSnapshotConfiguration(); config.snapshotWidth = 360; config.rect = view.bounds
        view.takeSnapshot(with: config) { [weak self, weak view] image, _ in
            guard let self else { return }
            self.snapshotInProgress = false
            guard self.liveWebView === view, self.url == capturedURL else { return }
            if let data = image?.jpegData(compressionQuality: 0.5), data.count <= 500_000 {
                self.previewData = data
                self.onPreview?(data, capturedURL, capturedTitle)
            }
            self.onStateChange?()
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { previousScrollY = 0 }
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging else { return }
        let current = scrollView.panGestureRecognizer.translation(in: scrollView).y
        defer { previousScrollY = current }
        guard let previousScrollY else { return }
        onVerticalScroll?(previousScrollY - current)
    }
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        let translation = scrollView.panGestureRecognizer.translation(in: scrollView)
        // Top-edge pulling can produce no didScroll callback on short pages.
        if translation.y > 25 && abs(translation.y) > abs(translation.x) && velocity.y <= 0 { onRevealChrome?() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { capturePreview() }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) { if !decelerate { capturePreview() } }

    func suspend() {
        guard !isProtectedForMedia, !snapshotInProgress, downloads.isEmpty else { return }
        releaseWebView(); isLoading = false; canGoBack = false; canGoForward = false
    }

    private func releaseWebView() {
        dialog?.resolve(nil); dialog = nil
        liveWebView?.scrollView.delegate = nil
        liveWebView?.stopLoading(); liveWebView?.navigationDelegate = nil; liveWebView?.uiDelegate = nil
        liveWebView?.configuration.userContentController.removeScriptMessageHandler(forName: "personalBrowserMedia")
        observations.removeAll(); appliedRule = nil; liveWebView = nil
        mediaFrames.removeAll(); pipFrames.removeAll(); hasActiveMedia = false; isPictureInPicture = false
    }

    func updateMedia(_ payload: [String: Any]) {
        guard let frame = payload["frame"] as? String else { return }
        mediaFrames[frame] = payload["playing"] as? Bool ?? false
        pipFrames[frame] = payload["pip"] as? Bool ?? false
        let active = mediaFrames.values.contains(true), pip = pipFrames.values.contains(true)
        guard active != hasActiveMedia || pip != isPictureInPicture else { return }
        hasActiveMedia = active; isPictureInPicture = pip
        if active {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
        }
        onStateChange?()
    }

    private static let mediaScript = """
    (() => {
      const frame = Math.random().toString(36).slice(2), players = new Set();
      let lastStatus = '';
      const report = () => {
        let playing = false, pip = false;
        players.forEach(v => { if (!v.isConnected) players.delete(v); else {
          playing ||= !v.paused && !v.ended;
          pip ||= v.webkitPresentationMode === 'picture-in-picture' || document.pictureInPictureElement === v;
        }});
        const status = (playing||pip) + ':' + pip;
        if (status === lastStatus) return;
        lastStatus = status;
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
        <p id="result"></p><div style="height:1800px">スクロール検証用のページ</div><p>ページの下部</p>
        """, baseURL: URL(string: "https://fixture.invalid"))
    }

    func dispose() {
        for (_, item) in downloads {
            item.0.cancel { _ in }
            if let target = item.1 { try? FileManager.default.removeItem(at: target) }
        }
        pendingConnection?.resolve(allow: false); pendingConnection = nil
        downloads.removeAll(); releaseWebView()
        prefersApplication = nil; onPreferBrowser = nil; onPreferApplication = nil
        onConnectionRequest = nil; trustsCertificate = nil; rememberCertificate = nil; rememberHTTP = nil
        onPreview = nil; onVerticalScroll = nil; onRevealChrome = nil; onVisit = nil; onStateChange = nil; onPopup = nil; onClose = nil; onExternalURL = nil
        onAnalyzeLink = nil; onMessageLink = nil; onSaveLink = nil; onOpenLink = nil; onShareLink = nil; onOpenInSafari = nil; onOpenInBrowser = nil; onDownload = nil
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
        errorMessage = nil; navigationGrants = [:]; certificateWarningShown = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        show(error)
    }

    private func show(_ error: Error) {
        let failure = error as NSError, code = (error as NSError).code
        if failure.domain == NSURLErrorDomain && code == NSURLErrorCancelled { return }
        if BrowserNavigationPolicy.isInterrupted(domain: failure.domain, code: code) {
            let failedURL = (failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
                ?? (failure.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
            expectedInterruptions = expectedInterruptions.filter { $0.value > Date() }
            if let failedURL, expectedInterruptions.removeValue(forKey: failedURL) != nil { return }
            if let request = lastTopLevelRequest, let target = request.url,
               failedURL == nil || failedURL == target,
               BrowserNavigationPolicy.canReplay(method: request.httpMethod, hasBody: request.httpBody != nil || request.httpBodyStream != nil),
               WebURLPolicy.allows(target), retriedInterruptedURLs.insert(target).inserted, let view = liveWebView {
                // Retry once through public load(_:), without the link-activation
                // app handoff. Never replay POSTs or hide persistent failures.
                view.load(request); return
            }
        }
        errorMessage = error.localizedDescription
        if [NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid].contains(code),
           let original = url, let alternative = ConnectionSecurity.httpAlternative(original), pendingConnection == nil, !certificateWarningShown {
            let request = ConnectionRequest(kind: .http, url: original) { [weak self] allow, remember in
                guard let self else { return }
                self.pendingConnection = nil
                if allow { if remember { self.rememberHTTP?(original) }; self.load(alternative) }
            }
            pendingConnection = request; onConnectionRequest?(request)
        }
    }

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else { completionHandler(.performDefaultHandling, nil); return }
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { completionHandler(.performDefaultHandling, nil); return }
        var parts = URLComponents(); parts.scheme = "https"; parts.host = challenge.protectionSpace.host
        parts.port = challenge.protectionSpace.port > 0 ? challenge.protectionSpace.port : 443
        guard let url = parts.url, let origin = ConnectionSecurity.origin(url), let certificate = SecTrustGetCertificateAtIndex(trust, 0) else {
            completionHandler(.cancelAuthenticationChallenge, nil); return
        }
        let fingerprint = SHA256.hash(data: SecCertificateCopyData(certificate) as Data).map { String(format: "%02x", $0) }.joined()
        if navigationGrants[origin] == fingerprint || trustsCertificate?(origin, fingerprint) == true {
            completionHandler(.useCredential, URLCredential(trust: trust)); return
        }
        pendingConnection?.resolve(allow: false)
        certificateWarningShown = true
        let request = ConnectionRequest(kind: .certificate, url: url, fingerprint: fingerprint) { [weak self] allow, remember in
            guard let self else { completionHandler(.cancelAuthenticationChallenge, nil); return }
            self.pendingConnection = nil
            if allow {
                self.navigationGrants[origin] = fingerprint
                if remember { self.rememberCertificate?(origin, fingerprint) }
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else { completionHandler(.cancelAuthenticationChallenge, nil) }
        }
        pendingConnection = request
        if let onConnectionRequest { onConnectionRequest(request) }
        else { request.resolve(allow: false) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        mediaFrames.removeAll(); pipFrames.removeAll(); hasActiveMedia = false; isPictureInPicture = false
        errorMessage = "ページの表示処理が終了しました。再読み込みしてください。"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        let topLevel = navigationAction.targetFrame?.isMainFrame != false
        let safeReplay = BrowserNavigationPolicy.canReplay(method: navigationAction.request.httpMethod,
            hasBody: navigationAction.request.httpBody != nil || navigationAction.request.httpBodyStream != nil)
        if WebURLPolicy.allows(url) && topLevel { lastTopLevelRequest = navigationAction.request }
        if WebURLPolicy.allows(url), topLevel, safeReplay,
           navigationAction.navigationType == .linkActivated, !navigationAction.shouldPerformDownload {
            let useApplication = prefersApplication?(url) == true
            if useApplication { expectedInterruptions[url] = Date().addingTimeInterval(5) }
            decisionHandler(.cancel)
            if useApplication {
                openRelatedApplication(url, remember: false) { [weak self] in self?.loadInBrowser(navigationAction.request, newWindow: navigationAction.targetFrame == nil) }
            } else { loadInBrowser(navigationAction.request, newWindow: navigationAction.targetFrame == nil) }
            return
        }
        if ["http", "https", "about", "blob", "data"].contains(scheme) {
            if navigationAction.shouldPerformDownload { decisionHandler(.download) }
            else if navigationAction.targetFrame?.isMainFrame == true {
                Task { @MainActor in
                    await self.configureBlocking(for: url, view: webView)
                    decisionHandler(.allow)
                }
            } else { decisionHandler(.allow) }
        } else {
            expectedInterruptions[url] = Date().addingTimeInterval(5)
            decisionHandler(.cancel)
            if ["mailto", "tel", "sms", "itms-apps"].contains(scheme), topLevel,
               navigationAction.navigationType == .linkActivated { onExternalURL?(url) }
        }
    }

    private func loadInBrowser(_ request: URLRequest, newWindow: Bool) {
        guard let url = request.url, WebURLPolicy.allows(url) else { return }
        if newWindow { if preferences.allowPopups { onOpenLink?(url, isPrivate) }; return }
        guard let view = liveWebView else { load(url); return }
        Task { @MainActor [weak self, weak view] in
            guard let self, let view else { return }
            await self.configureBlocking(for: url, view: view)
            guard self.liveWebView === view else { return }
            self.hasContent = true; self.url = url; view.load(request)
        }
    }
    private func openRelatedApplication(_ url: URL, remember: Bool = true, fallback: (() -> Void)? = nil) {
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { [weak self] opened in
            Task { @MainActor in
                guard let self else { return }
                if opened { if remember { self.onPreferApplication?(url) } }
                else if let fallback { fallback() }
                else { self.errorMessage = "このリンクに対応するアプリを開けませんでした。ブラウザで開くこともできます。" }
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
                self?.openRelatedApplication(link)
            }
            var appActions: [UIMenuElement] = []
            if WatchHTML.youtubeURL(link) != nil {
                appActions.append(UIAction(title: "YouTube", image: UIImage(systemName: "play.rectangle")) { [weak self] _ in
                    self?.openRelatedApplication(link)
                })
            }
            appActions += [related]
            appActions += applications
            appActions += [
                UIAction(title: "Safariの画面で開く", image: UIImage(systemName: "safari")) { [weak self] _ in self?.onOpenInSafari?(link) },
                UIAction(title: "既定のブラウザで開く", image: UIImage(systemName: "globe")) { [weak self] _ in self?.onOpenInBrowser?(link) },
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
                UIAction(title: "このタブで開く", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in self?.onPreferBrowser?(link); self?.load(link) },
                UIAction(title: "新しいタブで開く", image: UIImage(systemName: "plus.square")) { [weak self] _ in self?.onPreferBrowser?(link); self?.onOpenLink?(link, self?.isPrivate ?? false) },
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
        guard !store.overviewPresented, let selected = store.selectedTab else { return }
        let kept = store.tabs.filter { $0.id == selected.id || $0.isProtectedForMedia || $0.isCapturingPreview }
        let views = kept.compactMap { $0.id == selected.id && $0.hasContent ? $0.webView : $0.existingWebView }
        for view in host.subviews where !views.contains(where: { $0 === view }) { view.removeFromSuperview() }
        for tab in kept {
            guard let view = tab.existingWebView else { continue }
            if view.superview !== host { host.addSubview(view) }
            view.isUserInteractionEnabled = tab.id == selected.id && tab.hasContent
            // Do not hide a playing WebView or detach it on backgrounding.
            view.alpha = (tab.id == selected.id && tab.hasContent) || tab.isCapturingPreview ? 1 : 0.01
        }
        if let view = selected.existingWebView { host.bringSubviewToFront(view) }
        host.setNeedsLayout()
    }
}
final class WebSurfaceView: UIView {
    override func layoutSubviews() { super.layoutSubviews(); clipsToBounds = true; for view in subviews { view.frame = bounds } }
}
