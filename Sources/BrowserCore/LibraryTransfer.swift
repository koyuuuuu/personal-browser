import Foundation

public enum LibraryImportKind: String, CaseIterable, Identifiable, Sendable {
    case bookmarks, favorites, history
    public var id: String { rawValue }
    public var label: String { switch self { case .bookmarks: "ブックマーク"; case .favorites: "お気に入り"; case .history: "履歴" } }
}
public struct ImportedPage: Equatable, Sendable {
    public var title: String
    public var url: URL
    public var folders: [String] = []
    public var date: Date = Date()
    public init(title: String, url: URL, folders: [String] = [], date: Date = Date()) {
        self.title = title; self.url = url; self.folders = folders; self.date = date
    }
}
public enum LibraryTransferError: Error, LocalizedError {
    case tooLarge, unsupported, passwordFile, malformed
    public var errorDescription: String? {
        switch self {
        case .tooLarge: "ファイルは20MB、項目は50,000件以内にしてください。"
        case .unsupported: "URLを含むHTML・CSV・JSONファイルを選んでください。"
        case .passwordFile: "このファイルにはパスワードが含まれます。履歴やブックマークには取り込めません。"
        case .malformed: "ファイルの形式を読み取れませんでした。元のデータは変更していません。"
        }
    }
}

public enum LibraryTransfer {
    public static func parse(_ data: Data, kind: LibraryImportKind) throws -> [ImportedPage] {
        guard data.count <= 20 * 1024 * 1024 else { throw LibraryTransferError.tooLarge }
        guard let text = String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\u{FEFF}", with: "") else { throw LibraryTransferError.malformed }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pages: [ImportedPage]
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            let object = try JSONSerialization.jsonObject(with: data)
            pages = try parseJSON(object, kind: kind)
        } else if trimmed.lowercased().contains("<a ") || trimmed.lowercased().contains("<dl") {
            pages = parseHTML(trimmed)
        } else { pages = try parseCSV(trimmed) }
        guard !pages.isEmpty else { throw LibraryTransferError.unsupported }
        guard pages.count <= 50_000 else { throw LibraryTransferError.tooLarge }
        return pages
    }

    /// RFC 4180, including quoted commas, CRLF and quoted line breaks.
    public static func csvRows(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        let chars = Array(text.unicodeScalars); var i = 0; var quoted = false
        while i < chars.count {
            let c = chars[i]
            if c == "\"" {
                if quoted && i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 }
                else if field.isEmpty || quoted { quoted.toggle() }
                else { field.unicodeScalars.append(c) }
            } else if c == "," && !quoted { row.append(field); field = "" }
            else if (c == "\n" || c == "\r") && !quoted {
                row.append(field); field = ""
                if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
                row = []
                if c == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
            } else { field.unicodeScalars.append(c) }
            i += 1
        }
        guard !quoted else { throw LibraryTransferError.malformed }
        row.append(field); if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
        return rows
    }

    private static func parseCSV(_ text: String) throws -> [ImportedPage] {
        let rows = try csvRows(text)
        guard let first = rows.first else { return [] }
        let headers = first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if headers.contains(where: { ["password", "パスワード", "login_password"].contains($0) }) { throw LibraryTransferError.passwordFile }
        guard let urlIndex = headers.firstIndex(where: { ["url", "uri", "address", "website", "ページurl"].contains($0) }) else { throw LibraryTransferError.unsupported }
        let titleIndex = headers.firstIndex { ["title", "name", "タイトル"].contains($0) }
        let folderIndex = headers.firstIndex { ["folder", "folders", "フォルダ"].contains($0) }
        let dateIndex = headers.firstIndex { ["date", "visitedat", "visited_at", "last_visit_time", "visit_time"].contains($0) }
        return rows.dropFirst().compactMap { values in
            guard values.indices.contains(urlIndex), let url = URL(string: values[urlIndex]), WebURLPolicy.allows(url) else { return nil }
            func value(_ index: Int?) -> String? { index.flatMap { values.indices.contains($0) ? values[$0] : nil } }
            let folders = value(folderIndex)?.split(separator: "/").map(String.init) ?? []
            return ImportedPage(title: value(titleIndex) ?? url.host ?? url.absoluteString, url: url, folders: folders, date: parseDate(value(dateIndex)))
        }
    }

    private static func parseJSON(_ object: Any, kind: LibraryImportKind) throws -> [ImportedPage] {
        var result: [ImportedPage] = []
        func walk(_ node: Any, path: [String], depth: Int) throws {
            guard depth < 64, result.count <= 50_000 else { throw LibraryTransferError.tooLarge }
            if let array = node as? [Any] { for child in array { try walk(child, path: path, depth: depth + 1) }; return }
            guard let item = node as? [String: Any] else { return }
            if item.keys.contains(where: { ["password", "passwords", "logins", "encryptedPassword"].contains($0) }) { throw LibraryTransferError.passwordFile }
            if let address = (item["url"] ?? item["uri"]) as? String, let url = URL(string: address), WebURLPolicy.allows(url) {
                result.append(ImportedPage(title: (item["title"] ?? item["name"]) as? String ?? url.host ?? address, url: url, folders: (item["folders"] as? [String]) ?? path, date: parseDate((item["visitedAt"] ?? item["date"] ?? item["last_visit_time"]).map { String(describing: $0) })))
                return
            }
            if let children = item["children"] {
                let name = (item["title"] ?? item["name"]) as? String
                try walk(children, path: path + (name.flatMap { $0.isEmpty ? nil : [$0] } ?? []), depth: depth + 1)
            } else if let roots = item["roots"] as? [String: Any] {
                for key in roots.keys.sorted() { try walk(roots[key]!, path: path, depth: depth + 1) }
            } else if let entries = item[kind.rawValue] { try walk(entries, path: path, depth: depth + 1) }
            else if let entries = item["places"] { try walk(entries, path: path, depth: depth + 1) }
        }
        try walk(object, path: [], depth: 0)
        return result
    }

    private static func parseHTML(_ text: String) -> [ImportedPage] {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<H3\b[^>]*>(.*?)</H3>|<DL\b[^>]*>|</DL\s*>|<A\b[^>]*HREF\s*=\s*["']([^"']+)["'][^>]*>(.*?)</A>"#) else { return [] }
        let input = text as NSString
        var stack: [String?] = [], pending: String?, pages: [ImportedPage] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: input.length)) {
            let token = input.substring(with: match.range).uppercased()
            func capture(_ index: Int) -> String? { match.range(at: index).location == NSNotFound ? nil : unescape(input.substring(with: match.range(at: index))) }
            if let name = capture(1) { pending = name }
            else if token.hasPrefix("</DL") { if !stack.isEmpty { stack.removeLast() } }
            else if token.hasPrefix("<DL") { stack.append(pending); pending = nil }
            else if let address = capture(2), let url = URL(string: address), WebURLPolicy.allows(url) {
                pages.append(ImportedPage(title: capture(3) ?? url.host ?? address, url: url, folders: stack.compactMap { $0 }))
            }
        }
        return pages
    }

    private static func unescape(_ text: String) -> String {
        var value = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, replacement) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] { value = value.replacingOccurrences(of: entity, with: replacement) }
        return value
    }
    private static func parseDate(_ text: String?) -> Date {
        guard let text else { return Date() }
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        if let number = Double(text) {
            if number > 10_000_000_000_000_000 { return Date(timeIntervalSince1970: number / 1_000_000 - 11_644_473_600) }
            if number > 10_000_000_000_000 { return Date(timeIntervalSince1970: number / 1_000_000) }
            if number > 10_000_000_000 { return Date(timeIntervalSince1970: number / 1000) }
            return Date(timeIntervalSince1970: number)
        }
        return Date()
    }

    public static func export(bookmarks: [Bookmark], history: [HistoryEntry], extras: LibraryExtras) throws -> Data {
        struct ExportedBookmark: Encodable { var title: String; var url: URL; var folders: [String] }
        struct Backup: Encodable { var bookmarks: [ExportedBookmark]; var history: [HistoryEntry]; var favorites: [Bookmark] }
        let items = bookmarks.map { item -> ExportedBookmark in
            var names: [String] = [], parent = extras.bookmarkFolders[item.id.uuidString], seen = Set<UUID>()
            while let id = parent, seen.insert(id).inserted, let folder = extras.folders.first(where: { $0.id == id }) { names.insert(folder.name, at: 0); parent = folder.parentID }
            return ExportedBookmark(title: item.title, url: item.url, folders: names)
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Backup(bookmarks: items, history: history, favorites: extras.favorites))
    }
}
