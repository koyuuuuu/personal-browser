import Foundation

public struct SearchSuggestionPreferences: Codable, Equatable, Sendable {
    public var enabled = false
    public init() {}
}
public enum SearchSuggestions {
    public static func endpoint(_ input: String, engine: SearchEngine) -> URL? {
        let query = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 256, !query.contains("://"), !query.contains("@") else { return nil }
        var parts: URLComponents
        switch engine {
        case .google:
            parts = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
            parts.queryItems = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "q", value: query)]
        case .bing:
            parts = URLComponents(string: "https://api.bing.com/osjson.aspx")!
            parts.queryItems = [URLQueryItem(name: "query", value: query)]
        case .duckDuckGo:
            parts = URLComponents(string: "https://duckduckgo.com/ac/")!
            parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "list")]
        }
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return parts.url
    }
    public static func parse(_ data: Data, engine: SearchEngine) throws -> [String] {
        guard data.count <= 65_536 else { return [] }
        let json = try JSONSerialization.jsonObject(with: data)
        let values: [String]
        if engine == .duckDuckGo, let rows = json as? [[String: Any]] { values = rows.compactMap { $0["phrase"] as? String } }
        else if let array = json as? [Any], array.count > 1, let items = array[1] as? [String] { values = items }
        else { return [] }
        var seen = Set<String>()
        return Array(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count <= 256 && seen.insert($0).inserted }.prefix(6))
    }
}
