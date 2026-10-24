import Foundation

/// New presentation controls are separate from 0.3's features.json, which an
/// older app may rewrite. Older versions leave this file and preview files alone.
public struct PresentationPreferences: Codable, Equatable, Sendable {
    public var tabColumns = 2
    public var pageZoom = 1.0
    public var interfaceTextSize = InterfaceTextSize.system
    public var customAddressButtons = false
    public var addressLeft: [BrowserAction] = []
    public var addressRight: [BrowserAction] = []
    public var hideHomeIndicator = true
    public var backgroundAudio = true
    public var backgroundZoom = 1.0
    public var backgroundHorizontalOffset = 0.0
    public var backgroundVerticalOffset = 0.0
    public init() {}
    enum CodingKeys: String, CodingKey { case hideHomeIndicator, backgroundAudio, backgroundZoom, backgroundHorizontalOffset, backgroundVerticalOffset, tabColumns, pageZoom, interfaceTextSize, customAddressButtons, addressLeft, addressRight }
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tabColumns = try c.decodeIfPresent(Int.self, forKey: .tabColumns) ?? 2
        pageZoom = try c.decodeIfPresent(Double.self, forKey: .pageZoom) ?? 1
        interfaceTextSize = try c.decodeIfPresent(InterfaceTextSize.self, forKey: .interfaceTextSize) ?? .system
        customAddressButtons = try c.decodeIfPresent(Bool.self, forKey: .customAddressButtons) ?? false
        addressLeft = try c.decodeIfPresent([BrowserAction].self, forKey: .addressLeft) ?? []
        addressRight = try c.decodeIfPresent([BrowserAction].self, forKey: .addressRight) ?? []
        hideHomeIndicator = try c.decodeIfPresent(Bool.self, forKey: .hideHomeIndicator) ?? true
        backgroundAudio = try c.decodeIfPresent(Bool.self, forKey: .backgroundAudio) ?? true
        backgroundZoom = try c.decodeIfPresent(Double.self, forKey: .backgroundZoom) ?? 1
        backgroundHorizontalOffset = try c.decodeIfPresent(Double.self, forKey: .backgroundHorizontalOffset) ?? 0
        backgroundVerticalOffset = try c.decodeIfPresent(Double.self, forKey: .backgroundVerticalOffset) ?? 0
        self = normalized()
    }
    public func normalized() -> Self {
        var result = self
        result.tabColumns = min(4, max(1, tabColumns))
        result.pageZoom = pageZoom.isFinite ? min(2, max(0.75, pageZoom)) : 1
        var seen = Set<BrowserAction>(); result.addressLeft = addressLeft.filter { seen.insert($0).inserted }
        seen = []; result.addressRight = addressRight.filter { seen.insert($0).inserted }
        result.backgroundZoom = backgroundZoom.isFinite ? min(3, max(1, backgroundZoom)) : 1
        result.backgroundHorizontalOffset = backgroundHorizontalOffset.isFinite ? min(1, max(-1, backgroundHorizontalOffset)) : 0
        result.backgroundVerticalOffset = backgroundVerticalOffset.isFinite ? min(1, max(-1, backgroundVerticalOffset)) : 0
        return result
    }
}

public struct BackgroundPlacement: Equatable, Sendable {
    public var width: Double, height: Double, x: Double, y: Double
    public static func calculate(imageWidth: Double, imageHeight: Double, viewportWidth: Double, viewportHeight: Double, preferences: PresentationPreferences) -> Self {
        guard imageWidth > 0, imageHeight > 0, viewportWidth > 0, viewportHeight > 0 else { return Self(width: 0, height: 0, x: 0, y: 0) }
        let p = preferences.normalized(), scale = max(viewportWidth / imageWidth, viewportHeight / imageHeight)
        let width = imageWidth * scale * p.backgroundZoom, height = imageHeight * scale * p.backgroundZoom
        return Self(width: width, height: height,
                    x: viewportWidth / 2 + (width - viewportWidth) / 2 * p.backgroundHorizontalOffset,
                    y: viewportHeight / 2 + (height - viewportHeight) / 2 * p.backgroundVerticalOffset)
    }
}

public struct ChromeVisibility: Equatable, Sendable {
    public private(set) var landscape = false
    public private(set) var visible = true
    private var manuallyHidden = false
    private var accumulated = 0.0
    public init() {}
    public mutating func setLandscape(_ value: Bool) {
        guard value != landscape else { return }
        landscape = value; accumulated = 0
        visible = value ? false : !manuallyHidden
    }
    public mutating func hide() { visible = false; manuallyHidden = true; accumulated = 0 }
    public mutating func reveal() { visible = true; manuallyHidden = false; accumulated = 0 }
    /// Positive means moving towards the bottom of the document. Only a deliberate
    /// reverse scroll reveals the landscape row; tiny/bouncing offsets don't flap it.
    public mutating func scroll(delta: Double) {
        guard delta.isFinite, abs(delta) < 500 else { return }
        if delta * accumulated < 0 { accumulated = 0 }
        accumulated += delta
        if accumulated <= -18 { reveal() }
        else if landscape && accumulated >= 28 { visible = false; accumulated = 0 }
    }
}

public enum TabDestination: Equatable, Sendable { case existing(Int), create, none }
public enum TabNavigation {
    public static func destination(current: Int, count: Int, towardNext: Bool, maximum: Int = 500) -> TabDestination {
        guard count > 0, (0..<count).contains(current) else { return .none }
        let next = current + (towardNext ? 1 : -1)
        if (0..<count).contains(next) { return .existing(next) }
        return towardNext && count < maximum ? .create : .none
    }
}

public enum InterfaceTextSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, small, standard, large, extraLarge
    public var id: String { rawValue }
    public var label: String { switch self { case .system: "iOSの設定"; case .small: "小さめ"; case .standard: "標準"; case .large: "大きめ"; case .extraLarge: "さらに大きく" } }
}
