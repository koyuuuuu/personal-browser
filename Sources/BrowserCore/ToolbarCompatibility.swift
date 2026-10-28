import Foundation

extension ToolbarPreferences {
    /// Never expose new enum cases to the fixed readers of previously shipped apps.
    public func legacyCompatible() -> Self {
        var legacy = self
        if let main {
            let old = main.filter { !$0.isTabSelectionAction }
            legacy.main = old.isEmpty && !main.isEmpty ? nil : old
        }
        legacy.left = left.map { $0.filter { !$0.isTabSelectionAction } }
        legacy.right = right.map { $0.filter { !$0.isTabSelectionAction } }
        return legacy
    }
}

/// Stored separately; a rollback can edit toolbar.json without being overruled
/// by stale extension settings on the next upgrade.
public struct ExtendedToolbarPreferences: Codable, Equatable, Sendable {
    public var legacy: ToolbarPreferences
    public var full: ToolbarPreferences
    public init(_ full: ToolbarPreferences) { self.full = full; self.legacy = full.legacyCompatible() }
    public func resolve(against currentLegacy: ToolbarPreferences) -> ToolbarPreferences {
        legacy == currentLegacy ? full : currentLegacy
    }
}
