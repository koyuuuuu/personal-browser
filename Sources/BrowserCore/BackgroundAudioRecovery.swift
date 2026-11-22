import Foundation

/// Recovery is only for the brief app-to-Home transition, never an ongoing
/// policy of undoing pause commands. A fresh foreground transition is required
/// before another recovery can be armed.
public struct BackgroundAudioRecovery: Sendable {
    public private(set) var token: String?
    private var deadline: TimeInterval = 0
    private var consumed = false
    public init() {}
    public mutating func arm(token: String, now: TimeInterval) {
        self.token = token; deadline = now + 3; consumed = false
    }
    public mutating func consume(token: String, now: TimeInterval, background: Bool) -> Bool {
        guard background, self.token == token, !consumed, now <= deadline else { return false }
        consumed = true
        return true
    }
    public mutating func cancel() { token = nil; consumed = true }
}
