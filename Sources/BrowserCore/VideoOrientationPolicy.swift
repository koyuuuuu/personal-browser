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
