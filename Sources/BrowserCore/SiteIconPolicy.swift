import Foundation

public enum SiteIconPolicy {
    public static func origin(_ url: URL) -> URL? {
        guard WebURLPolicy.allows(url), url.user == nil, url.password == nil,
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.host != nil else { return nil }
        parts.path = "/"; parts.query = nil; parts.fragment = nil
        return parts.url
    }
    public static func permits(_ url: URL, from origin: URL) -> Bool {
        guard WebURLPolicy.allows(url), url.user == nil, url.password == nil else { return false }
        if ConnectionSecurity.isLocal(url) && !ConnectionSecurity.isLocal(origin) { return false }
        return url.scheme == "https" || (origin.scheme == "http" && url.host == origin.host && url.port == origin.port)
    }
    public static func candidates(in html: String, origin: URL) -> [URL] {
        guard let links = try? NSRegularExpression(pattern: "<link\\b[^>]{0,4096}>", options: [.caseInsensitive]),
              let attributes = try? NSRegularExpression(pattern: "(?:^|\\s)(rel|href)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", options: [.caseInsensitive]) else { return [] }
        let range = NSRange(html.startIndex..., in: html)
        var icons: [(Int, URL)] = []
        for link in links.matches(in: html, range: range).prefix(100) {
            guard let tagRange = Range(link.range, in: html) else { continue }
            let tag = String(html[tagRange]); var values: [String: String] = [:]
            for match in attributes.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                guard let key = Range(match.range(at: 1), in: tag) else { continue }
                for i in 2...4 where match.range(at: i).location != NSNotFound {
                    if let value = Range(match.range(at: i), in: tag) { values[String(tag[key]).lowercased()] = String(tag[value]) }
                }
            }
            let rel = (values["rel"] ?? "").lowercased().split(whereSeparator: { $0.isWhitespace })
            guard rel.contains("icon") || rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed"),
                  let href = values["href"], let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: origin)?.absoluteURL,
                  permits(url, from: origin) else { continue }
            icons.append((rel.contains("apple-touch-icon") ? 0 : 1, url))
        }
        var seen = Set<URL>()
        return icons.sorted { $0.0 < $1.0 }.map(\.1).filter { seen.insert($0).inserted }.prefix(4).map { $0 }
    }
}
