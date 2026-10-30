import Foundation

public enum SearchEngine: String, Codable, CaseIterable, Sendable {
    case duckDuckGo, google, bing

    public var label: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        }
    }

    public func searchURL(for query: String) -> URL {
        let base: String
        switch self {
        case .duckDuckGo: base = "https://duckduckgo.com/"
        case .google: base = "https://www.google.com/search"
        case .bing: base = "https://www.bing.com/search"
        }
        var components = URLComponents(string: base)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        // Search endpoints commonly decode '+' as a space in form-style queries.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

public enum AddressError: Error, LocalizedError, Equatable {
    case empty, unsupportedScheme, invalidURL, credentialsInURL

    public var errorDescription: String? {
        switch self {
        case .empty: "URLまたは検索語を入力してください。"
        case .unsupportedScheme: "アドレス欄ではHTTP・HTTPSのURLを開けます。"
        case .invalidURL: "URLを確認してください。"
        case .credentialsInURL: "ユーザー名やパスワードを含まないURLを使ってください。"
        }
    }
}

public enum WebURLPolicy {
    public static func allows(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return false }
        return true
    }
}

public enum AddressResolver {
    public static func resolve(_ text: String, engine: SearchEngine = .google) throws -> URL {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw AddressError.empty }
        if input.lowercased().hasPrefix("https:") || input.lowercased().hasPrefix("http:") {
            return try validatedURL(input)
        }
        if input.contains(where: { $0.isWhitespace }) {
            return engine.searchURL(for: input)
        }
        // A host:port is an address, even though a colon can also introduce a scheme.
        let candidate = URLComponents(string: "https://" + input)
        let host = candidate?.host ?? ""
        let isHost = host.contains(".") || host == "localhost" || host.contains(":")
        if isHost, !input.contains("://"), candidate?.user == nil, candidate?.password == nil {
            return try validatedURL("https://" + input)
        }
        if input.range(of: "^[A-Za-z][A-Za-z0-9+.-]*:", options: .regularExpression) != nil {
            throw AddressError.unsupportedScheme
        }
        return engine.searchURL(for: input)
    }

    private static func validatedURL(_ input: String) throws -> URL {
        guard let components = URLComponents(string: input), let url = components.url,
              let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw AddressError.invalidURL
        }
        guard components.user == nil, components.password == nil else {
            throw AddressError.credentialsInURL
        }
        guard WebURLPolicy.allows(url) else { throw AddressError.invalidURL }
        return url
    }
}
