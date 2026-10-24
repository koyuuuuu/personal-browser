import Foundation

public struct ConnectionPreferences: Codable, Equatable, Sendable {
    public var certificates: [String: String] = [:]
    public var httpOrigins: [String] = []
    public init() {}
    public func trusts(origin: String, fingerprint: String) -> Bool { certificates[origin] == fingerprint }
    public mutating func rememberCertificate(origin: String, fingerprint: String) throws {
        guard let url = URL(string: origin), url.scheme == "https", WebURLPolicy.allows(url),
              fingerprint.count == 64, fingerprint.allSatisfy({ $0.isHexDigit }) else { throw SnapshotError.invalidData }
        certificates[origin] = fingerprint.lowercased()
    }
}

public enum ConnectionSecurity {
    public static func origin(_ url: URL) -> String? {
        guard WebURLPolicy.allows(url), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme?.lowercased(); parts.host = parts.host?.lowercased(); parts.path = ""; parts.query = nil; parts.fragment = nil
        parts.port = parts.port ?? (parts.scheme == "https" ? 443 : 80)
        return parts.url?.absoluteString
    }
    public static func isLocal(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
        if host == "localhost" || host == "::1" || host.hasSuffix(".local") { return true }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 4 else { return false }
        let values = components.compactMap { Int($0) }
        guard values.count == 4, values.allSatisfy({ (0...255).contains($0) }) else { return false }
        return values[0] == 10 || values[0] == 127 || (values[0] == 192 && values[1] == 168) || (values[0] == 172 && (16...31).contains(values[1]))
    }
    public static func httpAlternative(_ url: URL) -> URL? {
        guard WebURLPolicy.allows(url), url.scheme?.lowercased() == "https", isLocal(url), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = "http"
        return parts.url
    }
    public static func preferredURL(_ url: URL, preferences: ConnectionPreferences) -> URL {
        guard let origin = origin(url), preferences.httpOrigins.contains(origin), let http = httpAlternative(url) else { return url }
        return http
    }
}
