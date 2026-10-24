import Foundation

public enum WatchHTML {
    public static func destination(address: String, video: URL) throws -> URL {
        guard WebURLPolicy.allows(video), let base = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              WebURLPolicy.allows(base), base.scheme == "https",
              var parts = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw UpdateFeedError.invalidURL }
        if parts.path.isEmpty || parts.path == "/" { parts.path = "/watch.html" }
        parts.fragment = nil
        var items = parts.queryItems ?? []; items.removeAll { $0.name == "url" }
        items.append(URLQueryItem(name: "url", value: video.absoluteString)); parts.queryItems = items
        guard let result = parts.url else { throw UpdateFeedError.invalidURL }
        return result
    }
    public static func youtubeURL(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(), ["youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be", "www.youtu.be"].contains(host), WebURLPolicy.allows(url) else { return nil }
        return url
    }
}
