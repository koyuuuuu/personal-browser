import Foundation

public enum ToolbarPosition: String, Codable, CaseIterable, Sendable {
    case top, bottom
}

public enum BrowserAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case back, forward, reload, newTab, tabs, bookmarks, share
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .back: "戻る"
        case .forward: "進む"
        case .reload: "再読み込み"
        case .newTab: "新しいタブ"
        case .tabs: "タブ一覧"
        case .bookmarks: "ブックマーク"
        case .share: "共有"
        }
    }
    public var symbol: String {
        switch self {
        case .back: "chevron.left"
        case .forward: "chevron.right"
        case .reload: "arrow.clockwise"
        case .newTab: "plus"
        case .tabs: "square.on.square"
        case .bookmarks: "book"
        case .share: "square.and.arrow.up"
        }
    }
}

public struct BrowserSettings: Codable, Equatable, Sendable {
    public var toolbarPosition: ToolbarPosition = .bottom
    public var searchEngine: SearchEngine = .duckDuckGo
    public var swipeNavigation: Bool = true
    public var actions: [BrowserAction] = [.back, .forward, .reload, .tabs, .bookmarks]
    public init() {}

    public func normalized() -> Self {
        var copy = self
        var seen = Set<BrowserAction>()
        copy.actions = actions.filter { seen.insert($0).inserted }
        return copy
    }
}

public struct Bookmark: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public init(id: UUID = UUID(), title: String, url: URL) {
        self.id = id
        self.title = title
        self.url = url
    }
}

public struct HistoryEntry: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var url: URL
    public var visitedAt: Date
    public init(id: UUID = UUID(), title: String, url: URL, visitedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.url = url
        self.visitedAt = visitedAt
    }
}

public struct TabRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var url: URL?
    public init(id: UUID = UUID(), url: URL? = nil) {
        self.id = id
        self.url = url
    }
}

public struct TabState: Equatable, Sendable {
    public var record: TabRecord
    public var isPrivate: Bool
    public init(record: TabRecord, isPrivate: Bool) {
        self.record = record
        self.isPrivate = isPrivate
    }
}

public struct SessionSnapshot: Codable, Equatable, Sendable {
    public var tabs: [TabRecord]
    public var selectedID: UUID?

    public init(tabs: [TabRecord] = [], selectedID: UUID? = nil) {
        self.tabs = tabs
        self.selectedID = selectedID
    }

    public static func capture(_ states: [TabState], selectedID: UUID?) -> Self {
        let records = states.filter { !$0.isPrivate }.map(\.record)
        let selected = records.contains { $0.id == selectedID } ? selectedID : records.first?.id
        return Self(tabs: records, selectedID: selected)
    }
}

public enum SnapshotError: Error, LocalizedError {
    case unsupportedVersion, invalidData
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "この保存データのバージョンには対応していません。"
        case .invalidData: "保存データの内容を確認してください。"
        }
    }
}

public struct BrowserSnapshot: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var settings = BrowserSettings()
    public var bookmarks: [Bookmark] = []
    public var history: [HistoryEntry] = []
    public var session = SessionSnapshot()
    public init() {}

    public func validated() throws -> Self {
        guard schemaVersion == 1 else { throw SnapshotError.unsupportedVersion }
        guard bookmarks.allSatisfy({ WebURLPolicy.allows($0.url) }),
              history.allSatisfy({ WebURLPolicy.allows($0.url) }),
              session.tabs.allSatisfy({ $0.url == nil || WebURLPolicy.allows($0.url!) }),
              Set(bookmarks.map(\.id)).count == bookmarks.count,
              Set(session.tabs.map(\.id)).count == session.tabs.count else {
            throw SnapshotError.invalidData
        }
        var copy = self
        copy.settings = settings.normalized()
        copy.history = Array(history.prefix(1000))
        copy.session.tabs = Array(session.tabs.prefix(12))
        if !copy.session.tabs.contains(where: { $0.id == copy.session.selectedID }) {
            copy.session.selectedID = copy.session.tabs.first?.id
        }
        return copy
    }

    public mutating func recordVisit(url: URL, title: String, isPrivate: Bool, at date: Date = Date()) {
        guard !isPrivate, WebURLPolicy.allows(url) else { return }
        history.removeAll { $0.url == url }
        history.insert(HistoryEntry(title: title, url: url, visitedAt: date), at: 0)
        history = Array(history.prefix(1000))
    }
}
