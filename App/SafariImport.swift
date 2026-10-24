import Foundation


/// Uses Apple's Compression framework instead of embedding a third-party ZIP library.
enum SafariImport {
    static func parse(_ data: Data, kind: LibraryImportKind) throws -> [ImportedPage] {
        guard data.starts(with: [0x50, 0x4b]) else { return try LibraryTransfer.parse(data, kind: kind) }
        let entries = try BrowserArchive.entries(in: data, kind: kind)
        var pages: [ImportedPage] = []
        for entry in entries {
            let contents = try BrowserArchive.contents(of: entry)
            do { pages += try LibraryTransfer.parse(contents, kind: kind) }
            catch LibraryTransferError.unsupported { continue }
            guard pages.count <= 50_000 else { throw LibraryTransferError.tooLarge }
        }
        guard !pages.isEmpty else { throw LibraryTransferError.unsupported }
        return pages
    }
}
