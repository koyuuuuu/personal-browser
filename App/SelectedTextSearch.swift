import Foundation

extension BrowserStore {
    func searchSelection(_ text: String, from tab: BrowserTab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        do {
            let url = try TextSearch.url(text, engine: snapshot.settings.searchEngine)
            _ = newTab(isPrivate: tab.isPrivate, url: url, after: tab.id)
        } catch { notice = error.localizedDescription }
    }
}
