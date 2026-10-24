import Foundation

public struct BookmarkFolder: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var parentID: UUID?
    public init(id: UUID = UUID(), name: String, parentID: UUID? = nil) {
        self.id = id; self.name = name; self.parentID = parentID
    }
}

/// Kept outside browser.json so old builds preserve the latest shared library.
public struct LibraryExtras: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var favorites: [Bookmark] = []
    public var folders: [BookmarkFolder] = []
    public var bookmarkFolders: [String: UUID] = [:]
    public init() {}

    public func canMoveFolder(_ id: UUID, to parent: UUID?) -> Bool {
        var next = parent
        var visited = Set<UUID>()
        while let current = next {
            guard current != id, visited.insert(current).inserted else { return false }
            next = folders.first { $0.id == current }?.parentID
        }
        return true
    }

    public mutating func removeFolder(_ id: UUID) {
        let parent = folders.first { $0.id == id }?.parentID
        for index in folders.indices where folders[index].parentID == id { folders[index].parentID = parent }
        for (bookmark, folder) in bookmarkFolders where folder == id { bookmarkFolders[bookmark] = parent }
        folders.removeAll { $0.id == id }
    }

    public func validated() throws -> Self {
        guard schemaVersion == 1, Set(folders.map(\.id)).count == folders.count,
              Set(favorites.map(\.id)).count == favorites.count,
              favorites.allSatisfy({ WebURLPolicy.allows($0.url) }),
              folders.allSatisfy({ canMoveFolder($0.id, to: $0.parentID) }) else { throw SnapshotError.invalidData }
        return self
    }
}

public struct FeaturePreferences: Codable, Equatable, Sendable {
    public var watchHTMLAddress = ""
    public var blockAdvertisements = true
    public var blockingExceptions: [String] = []
    public var swipeAddressToSwitchTabs = true
    public var animateNewTabs = true
    public var showHomeBackground = true
    public var favoriteColumns = 4
    public var maximumLiveTabs = 4
    public var enablePictureInPicture = true
    public var allowPopups = true
    public var externalApplications: [String] = ["chrome", "firefox", "brave", "edge"]
    public init() {}

    public func shouldBlock(_ url: URL?) -> Bool {
        guard blockAdvertisements else { return false }
        guard let host = url?.host?.lowercased() else { return true }
        return !blockingExceptions.contains { host == $0 || host.hasSuffix("." + $0) }
    }
}

public enum ExternalApplication: String, CaseIterable, Identifiable, Sendable {
    case chrome, firefox, brave, edge
    public var id: String { rawValue }
    public var label: String {
        switch self { case .chrome: "Chrome"; case .firefox: "Firefox"; case .brave: "Brave"; case .edge: "Edge" }
    }
    public func destination(for url: URL) -> URL? {
        guard WebURLPolicy.allows(url) else { return nil }
        if self == .chrome || self == .edge {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.scheme = self == .chrome ? (url.scheme == "https" ? "googlechromes" : "googlechrome") : (url.scheme == "https" ? "microsoft-edge-https" : "microsoft-edge-http")
            return parts?.url
        }
        var parts = URLComponents()
        parts.scheme = rawValue; parts.host = "open-url"
        parts.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
        return parts.url
    }
}
