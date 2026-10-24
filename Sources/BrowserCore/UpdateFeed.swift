import Foundation

public struct AppBuild: Equatable, Comparable, Sendable {
    public let version: [Int]
    public let build: Int

    public init?(version: String, build: String) {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let number = Int(build), number >= 0 else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        self.version = numbers + Array(repeating: 0, count: 3 - numbers.count)
        self.build = number
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.version != rhs.version { return lhs.version.lexicographicallyPrecedes(rhs.version) }
        return lhs.build < rhs.build
    }
}

public struct BrowserUpdate: Equatable, Sendable {
    public let version: String
    public let buildVersion: String
    public let description: String?
    public var displayVersion: String { "\(version) (\(buildVersion))" }
}

public enum UpdateFeedError: Error {
    case invalidURL, invalidFeed
}

public enum UpdateFeed {
    public static let bundleIdentifier = "local.personalbrowser.app"

    public static func sourceURL(_ text: String) throws -> URL {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil else {
            throw UpdateFeedError.invalidURL
        }
        return url
    }

    /// The first source version is the publisher's selected version, including
    /// deliberate rollbacks. Do not replace it with a numerically highest entry.
    public static func available(in data: Data, current: AppBuild) throws -> BrowserUpdate? {
        struct Source: Decodable { let apps: [App] }
        struct App: Decodable { let bundleIdentifier: String; let versions: [Version] }
        struct Version: Decodable {
            let version: String
            let buildVersion: String
            let localizedDescription: String?
        }
        guard data.count <= 1_048_576 else { throw UpdateFeedError.invalidFeed }
        let source = try JSONDecoder().decode(Source.self, from: data)
        guard let app = source.apps.first(where: { $0.bundleIdentifier == bundleIdentifier }),
              let version = app.versions.first,
              let proposed = AppBuild(version: version.version, build: version.buildVersion) else {
            throw UpdateFeedError.invalidFeed
        }
        guard proposed > current else { return nil }
        return BrowserUpdate(version: version.version, buildVersion: version.buildVersion,
                             description: version.localizedDescription)
    }
}
