import Foundation

/// Independent of legacy BrowserSettings.actions so old snapshot readers never
/// encounter an unknown legacy enum case when new address-bar functions expand.
public enum AddressBarAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case back, forward, reload, newTab, tabs, bookmarks, share
    case home, history, find, downloads, watchHTML, favorite, addBookmark, settings, zoomIn, zoomOut
    public var id: String { rawValue }
    public init(legacy: BrowserAction) { self = Self(rawValue: legacy.rawValue)! }
    public var legacy: BrowserAction? { BrowserAction(rawValue: rawValue) }
    public var label: String {
        if let legacy { return legacy.label }
        switch self {
        case .zoomIn: return "ページを5％拡大"
        case .zoomOut: return "ページを5％縮小"
        case .home: return "ホーム"
        case .history: return "履歴"
        case .find: return "ページ内を検索"
        case .downloads: return "ダウンロード"
        case .watchHTML: return "コピーしたリンクをWatch HTMLで解析"
        case .favorite: return "お気に入りに追加"
        case .addBookmark: return "ブックマークに追加"
        case .settings: return "設定"
        default: return rawValue
        }
    }
    public var symbol: String {
        if let legacy { return legacy.symbol }
        switch self {
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .home: return "house"
        case .history: return "clock"
        case .find: return "magnifyingglass"
        case .downloads: return "arrow.down.circle"
        case .watchHTML: return "play.rectangle.on.rectangle"
        case .favorite: return "star"
        case .addBookmark: return "bookmark"
        case .settings: return "slider.horizontal.3"
        default: return "ellipsis.circle"
        }
    }
}
