import Foundation

public enum IncomingBrowserLink {
    public static func destination(_ incoming: URL, engine: SearchEngine = .google) throws -> URL {
        guard incoming.absoluteString.utf8.count <= 262_144,
              let parts = URLComponents(url: incoming, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "mybrowser", ["open", "search"].contains(parts.host?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty || parts.path == "/", parts.fragment == nil,
              let items = parts.queryItems, items.count == 1,
              let value = items[0].value, !value.isEmpty else { throw AddressError.invalidURL }
        if parts.host?.lowercased() == "search" {
            guard items[0].name == "text" else { throw AddressError.invalidURL }
            return try TextSearch.url(value, engine: engine)
        }
        guard items[0].name == "url",
              !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let target = URLComponents(string: value),
              let url = target.url, WebURLPolicy.allows(url),
              target.port.map({ (1...65535).contains($0) }) ?? true,
              !(target.host?.contains(where: { $0.isWhitespace }) ?? true) else { throw AddressError.invalidURL }
        return url
    }
    public static func make(_ url: URL) -> URL? {
        guard WebURLPolicy.allows(url) else { return nil }
        var parts = URLComponents(); parts.scheme = "mybrowser"; parts.host = "open"
        parts.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
}

/// This browser's preference, not an iOS-wide Universal Links setting.
/// Kept separately so the 0.4.2 rollback baseline can still read its files.
public struct LinkPreferences: Codable, Equatable, Sendable {
    public var applicationSites = Set<String>()
    public init() {}
    public static func site(_ url: URL) -> String? {
        guard WebURLPolicy.allows(url), var host = url.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        for (key, domains) in [("x.com", ["x.com", "twitter.com"]), ("youtube.com", ["youtube.com", "youtu.be"])] {
            if domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return key }
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
    public mutating func preferApplication(_ enabled: Bool, for url: URL) {
        guard let site = Self.site(url) else { return }
        if enabled { applicationSites.insert(site) } else { applicationSites.remove(site) }
    }
    public func opensApplication(_ url: URL) -> Bool { Self.site(url).map { applicationSites.contains($0) } ?? false }
}

public enum SearchAddress {
    public struct Query: Equatable, Sendable { public var text: String; public var engine: SearchEngine }
    public static func query(_ url: URL) -> Query? {
        guard WebURLPolicy.allows(url), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = parts.host?.lowercased() else { return nil }
        let engine: SearchEngine
        if ["google.com", "www.google.com", "google.co.jp", "www.google.co.jp", "google.co.uk", "www.google.co.uk", "google.de", "www.google.de", "google.fr", "www.google.fr"].contains(host), parts.path == "/search" { engine = .google }
        else if ["bing.com", "www.bing.com"].contains(host), parts.path == "/search" { engine = .bing }
        else if ["duckduckgo.com", "www.duckduckgo.com", "html.duckduckgo.com"].contains(host), ["", "/", "/html/", "/html"].contains(parts.path) { engine = .duckDuckGo }
        else { return nil }
        // Decode form-style + only before percent-decoding, preserving %2B.
        var form = parts; form.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        guard let text = form.queryItems?.first(where: { $0.name == "q" })?.value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Query(text: text, engine: engine)
    }
    public static func display(_ url: URL?) -> String { url.map { query($0)?.text ?? $0.absoluteString } ?? "" }
    public static func submission(_ input: String, current: URL?, defaultEngine: SearchEngine) throws -> URL {
        if let current, let query = query(current) {
            let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw AddressError.empty }
            // A real address still navigates; single-word edits remain a search
            // in the engine whose results are being edited.
            return try AddressResolver.resolve(text, engine: query.engine)
        }
        return try AddressResolver.resolve(input, engine: defaultEngine)
    }
}

public enum BrowserNavigationPolicy {
    public static func canReplay(method: String?, hasBody: Bool) -> Bool {
        !hasBody && ["GET", "HEAD"].contains((method ?? "GET").uppercased())
    }
    public static func isInterrupted(domain: String, code: Int) -> Bool { domain == "WebKitErrorDomain" && code == 102 }
}
