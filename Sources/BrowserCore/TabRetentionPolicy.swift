import Foundation

/// Page residency is independent of the legacy library/session format.
public enum TabRetentionPolicy {
    public static let standardLimit = 12
    public static let memoryPressureLimit = 4
    public static func normalized(_ limit: Int) -> Int { min(24, max(8, limit)) }
    public static func needsEviction(liveCount: Int, limit: Int) -> Bool { liveCount > limit }
}
