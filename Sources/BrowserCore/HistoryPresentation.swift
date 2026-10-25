import Foundation

public struct HistoryPeriod: Identifiable, Equatable, Sendable {
    public var id: Date
    public var afternoon: Bool
    public var entries: [HistoryEntry]
}

public enum HistoryPresentation {
    /// Calendar dates (including DST) rather than fixed 12-hour Unix buckets.
    public static func periods(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [HistoryPeriod] {
        let groups = Dictionary(grouping: entries) { entry in
            let day = calendar.startOfDay(for: entry.visitedAt)
            return calendar.component(.hour, from: entry.visitedAt) < 12 ? day : calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        }
        return groups.keys.sorted(by: >).map { date in
            HistoryPeriod(id: date, afternoon: calendar.component(.hour, from: date) >= 12,
                          entries: groups[date]!.sorted { $0.visitedAt > $1.visitedAt })
        }
    }

    public static func suggestions(_ query: String, history: [HistoryEntry], limit: Int = 5) -> [HistoryEntry] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var seen = Set<URL>()
        return Array(history.sorted { $0.visitedAt > $1.visitedAt }.filter {
            ($0.title.localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query)) && seen.insert($0.url).inserted
        }.prefix(max(0, limit)))
    }
}

/// New actions live outside legacy presentation.json/browser.json. Old versions
/// can still read all their own settings when zoom buttons have been configured.
public struct ToolbarPreferences: Codable, Equatable, Sendable {
    public var main: [AddressBarAction]?
    public var left: [AddressBarAction]?
    public var right: [AddressBarAction]?
    public init() {}
}

public enum PageMagnification {
    public static func step(_ value: Double, increase: Bool) -> Double {
        min(2, max(0.75, ((value * 100).rounded() + (increase ? 5 : -5)) / 100))
    }
}
