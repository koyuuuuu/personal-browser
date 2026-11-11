import Foundation

public enum VideoTilt: Equatable, Sendable {
    case portrait, landscapeLeft, landscapeRight
    public static func gravity(x: Double, y: Double, z: Double) -> Self? {
        guard x.isFinite, y.isFinite, z.isFinite, abs(z) < 0.85 else { return nil }
        if abs(x) > 0.72 && abs(x) > abs(y) * 1.25 { return x > 0 ? .landscapeLeft : .landscapeRight }
        if y < -0.72 && abs(y) > abs(x) * 1.25 { return .portrait }
        return nil
    }
    public static func forVideo(width: Double, height: Double, tilt: Self) -> Self? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
        return width > height ? (tilt == .portrait ? .landscapeRight : tilt) : .portrait
    }
}

public enum TabGridMetrics {
    public static func width(viewport: Double, horizontalInsets: Double, columns: Int) -> Double {
        let count = min(4, max(1, columns))
        return floor(max(1, viewport - max(0, horizontalInsets) - 32 - Double(count - 1) * 16) / Double(count))
    }
}

/// A scene may briefly keep its previous geometry during fullscreen changes.
/// Apply once, allow one correction, and stop on denial until the target changes.
public struct VideoOrientationRequestPolicy: Sendable {
    public private(set) var target: VideoTilt?
    public private(set) var repaired = false
    public private(set) var rejected = false
    public init() {}
    public mutating func shouldRequest(_ target: VideoTilt, current: VideoTilt?) -> Bool {
        if self.target != target {
            self.target = target; repaired = false; rejected = false
            return true
        }
        guard !rejected, !repaired, let current, current != target else { return false }
        repaired = true
        return true
    }
    public mutating func reject() { rejected = true }
    public mutating func reset() { self = Self() }
}
