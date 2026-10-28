import Foundation

/// Tab activation order, independent of page history and WebView eviction order.
/// Intentionally not Codable: private-tab visits never enter saved sessions.
public struct TabSelectionHistory: Equatable, Sendable {
    public private(set) var entries: [UUID] = []
    public private(set) var cursor = -1
    public var current: UUID? { entries.indices.contains(cursor) ? entries[cursor] : nil }
    public var canGoBack: Bool { cursor > 0 }
    public var canGoForward: Bool { cursor >= 0 && cursor + 1 < entries.count }
    public init() {}

    public mutating func visit(_ id: UUID) {
        guard current != id else { return }
        if cursor + 1 < entries.count { entries.removeSubrange((cursor + 1)..<entries.count) }
        entries.append(id)
        if entries.count > 4096 { entries.removeFirst(entries.count - 4096) }
        cursor = entries.count - 1
    }
    public mutating func step(forward: Bool) -> UUID? {
        guard forward ? canGoForward : canGoBack else { return nil }
        cursor += forward ? 1 : -1
        return current
    }
    public mutating func retain(openIDs: Set<UUID>) {
        var kept: [UUID] = [], position = -1
        for (index, id) in entries.enumerated() where openIDs.contains(id) {
            if kept.last != id { kept.append(id) }
            if index <= cursor { position = kept.count - 1 }
        }
        entries = kept
        cursor = kept.isEmpty ? -1 : max(0, position)
    }
}

public enum TabInsertion {
    public static func index(after opener: UUID?, in tabs: [UUID]) -> Int {
        guard let opener, let index = tabs.firstIndex(of: opener) else { return tabs.count }
        return index + 1
    }
}
