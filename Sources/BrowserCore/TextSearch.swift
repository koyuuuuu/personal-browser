import Foundation

public enum TextSearchError: Error, LocalizedError {
    case empty, tooLong
    public var errorDescription: String? {
        switch self {
        case .empty: "検索するテキストを選択してください。"
        case .tooLong: "検索するテキストはUTF-8で16KB以内にしてください。短い範囲を選択し直してください。"
        }
    }
}

public enum TextSearch {
    public static let maximumUTF8Bytes = 16_384
    /// Always searches, including text that happens to look like a URL.
    public static func url(_ text: String, engine: SearchEngine = .google) throws -> URL {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw TextSearchError.empty }
        guard query.utf8.count <= maximumUTF8Bytes else { throw TextSearchError.tooLong }
        return engine.searchURL(for: query)
    }
    public static func incomingLink(_ text: String) throws -> URL {
        _ = try url(text)
        var parts = URLComponents(); parts.scheme = "mybrowser"; parts.host = "search"
        parts.queryItems = [URLQueryItem(name: "text", value: text.trimmingCharacters(in: .whitespacesAndNewlines))]
        parts.percentEncodedQuery = parts.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let link = parts.url else { throw AddressError.invalidURL }
        return link
    }
}
