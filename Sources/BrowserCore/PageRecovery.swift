import Foundation

/// Event-driven, bounded retries. Never resend a form or retry a trust/policy
/// rejection. A subsequent failure is left for the user's explicit action.
public struct PageRecoveryPolicy: Sendable {
    private var lastAttempt: Date?
    public init() {}
    public mutating func userNavigation() { lastAttempt = nil }
    public static func isTransient(domain: String, code: Int) -> Bool {
        domain == NSURLErrorDomain && [NSURLErrorTimedOut, NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed, NSURLErrorNotConnectedToInternet].contains(code)
    }
    public mutating func claim(method: String?, hasBody: Bool, now: Date = Date()) -> Bool {
        guard BrowserNavigationPolicy.canReplay(method: method, hasBody: hasBody),
              lastAttempt.map({ now.timeIntervalSince($0) >= 60 }) ?? true else { return false }
        lastAttempt = now
        return true
    }
}

public enum ChromeRecoveryGesture {
    /// Finger movement, independent of WebKit's content-offset callbacks.
    /// Forward motion on a normal long document (including bottom bounce)
    /// keeps its usual behavior; blocked/short pages have an escape both ways.
    public static func shouldReveal(startedHidden: Bool, x: Double, y: Double,
                                    contentTravel: Double, scrollable: Bool, locked: Bool) -> Bool {
        guard startedHidden, x.isFinite, y.isFinite, contentTravel.isFinite,
              abs(y) >= 24, abs(y) > abs(x) * 1.3 else { return false }
        return y > 0 || ((!scrollable || locked) && contentTravel < 4)
    }
}

public enum BrowserSitePolicy {
    public static func isReddit(_ url: URL?) -> Bool {
        guard let url, WebURLPolicy.allows(url), let host = url.host?.lowercased() else { return false }
        return host == "reddit.com" || host.hasSuffix(".reddit.com")
    }
    /// Explicit fallback only. Do not send Reddit paths/queries to another site.
    public static func redditWebAlternative(_ url: URL?) -> URL? {
        guard isReddit(url), let url, url.host?.lowercased() != "old.reddit.com",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "https"; parts.host = "old.reddit.com"; parts.port = nil
        parts.user = nil; parts.password = nil
        return parts.url
    }
}
