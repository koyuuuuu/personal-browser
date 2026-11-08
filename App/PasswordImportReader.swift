import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// This path is separate from library import. It never writes plaintext files.
enum PasswordImportReader {
    static func read(_ url: URL) throws -> PasswordImportResult {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let data = try PasswordVault.readLimited(url, limit: 20 * 1024 * 1024)
        return try parse(data, isZIP: url.pathExtension.lowercased() == "zip")
    }
    static func parse(_ data: Data, isZIP: Bool) throws -> PasswordImportResult {
        if !isZIP { return try PasswordCSV.parse(data) }
        let entries = try BrowserArchive.passwordEntries(in: data)
        var result = PasswordImportResult(), expanded = 0
        for entry in entries {
            let contents = try BrowserArchive.contents(of: entry)
            expanded += contents.count
            guard expanded <= 16 * 1024 * 1024 else { throw PasswordVaultError.tooLarge }
            let part = try PasswordCSV.parse(contents)
            result.records += part.records; result.skipped += part.skipped; result.ignoredCodes += part.ignoredCodes
            guard result.records.count <= 5000 else { throw PasswordVaultError.tooLarge }
        }
        guard !result.records.isEmpty else { throw PasswordVaultError.invalidImport }
        return result
    }
}

struct EncryptedPasswordDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data = Data()
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, data.count <= 12 * 1024 * 1024 else { throw PasswordVaultError.tooLarge }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
