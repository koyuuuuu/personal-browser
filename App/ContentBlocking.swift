import Foundation
import WebKit

/// Small original rule set. No downloaded JavaScript, remote filter subscription,
/// or browsing URL is sent to a filtering service.
@MainActor
final class ContentBlocking {
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
            return await withCheckedContinuation { continuation in
                WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "PersonalBrowser-ads-v1", encodedContentRuleList: json) { list, _ in continuation.resume(returning: list) }
            }
        }
        task = operation
        return await operation.value
    }
}
