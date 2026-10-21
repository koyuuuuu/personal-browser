import Foundation

public struct SnapshotStore: Sendable {
    public let fileURL: URL
    public init(fileURL: URL) { self.fileURL = fileURL }

    public func load() throws -> BrowserSnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return BrowserSnapshot() }
        return try JSONDecoder().decode(BrowserSnapshot.self, from: Data(contentsOf: fileURL)).validated()
    }

    public func save(_ snapshot: BrowserSnapshot) throws {
        let validated = try snapshot.validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(validated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
