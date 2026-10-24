import Foundation
import Combine
import WebKit

/// Small original rule set. No downloaded JavaScript, remote filter subscription,
/// or browsing URL is sent to a filtering service.
@MainActor
final class ContentBlocking: ObservableObject {
    @Published private(set) var status = "内蔵ルールを準備中…"
    static let shared = ContentBlocking()
    private var task: Task<WKContentRuleList?, Never>?
    static let domains = ["doubleclick.net", "googlesyndication.com", "googleadservices.com", "adservice.google.com", "adsystem.com", "amazon-adsystem.com", "adnxs.com", "adsrvr.org", "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "pubmatic.com", "rubiconproject.com", "openx.net", "casalemedia.com", "smartadserver.com", "scorecardresearch.com", "quantserve.com", "advertising.com"]

    func rules() async -> WKContentRuleList? {
        if let task { return await task.value }
        let operation = Task { @MainActor () -> WKContentRuleList? in
            let rules: [[String: Any]] = Self.domains.map { domain in
                let escaped = domain.replacingOccurrences(of: ".", with: "\\.")
                return ["trigger": ["url-filter": "^https?://([^/]+\\.)?" + escaped + "[:/]", "load-type": ["third-party"]], "action": ["type": "block"]]
            }
            guard let data = try? JSONSerialization.data(withJSONObject: rules), let json = String(data: data, encoding: .utf8) else { return nil }
            let result: WKContentRuleList? = await withCheckedContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "PersonalBrowser-ads-v1", encodedContentRuleList: json) { list, _ in continuation.resume(returning: list) }
            }
            self.status = result == nil ? "内蔵ルールの準備に失敗しました" : "内蔵ルールを準備しました"
            return result
        }
        task = operation
        return await operation.value
    }
}
