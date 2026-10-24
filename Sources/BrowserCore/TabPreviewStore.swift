import Foundation

public struct TabPreviewRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var url: URL
    public var title: String
    public var imageID: UUID
    public var capturedAt: Date
    public var fileName: String { id.uuidString + "-" + imageID.uuidString + ".jpg" }
}

/// No TTL; Application Support is intentionally used rather than Library/Caches.
/// Each image generation is written before an atomic manifest switch.
public final class TabPreviewStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    public func records() throws -> [TabPreviewRecord] {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        let data = try Data(contentsOf: indexURL)
        guard data.count < 2_000_000 else { throw SnapshotError.invalidData }
        let values = try JSONDecoder().decode([TabPreviewRecord].self, from: data)
        guard Set(values.map(\.id)).count == values.count, values.allSatisfy({ WebURLPolicy.allows($0.url) }) else { throw SnapshotError.invalidData }
        return values
    }
    @discardableResult
    public func save(id: UUID, url: URL, title: String, image: Data, isPrivate: Bool) throws -> TabPreviewRecord? {
        guard !isPrivate else { return nil }
        guard WebURLPolicy.allows(url), !image.isEmpty, image.count <= 500_000 else { throw SnapshotError.invalidData }
        var values = try records()
        let old = values.first { $0.id == id }
        let record = TabPreviewRecord(id: id, url: url, title: title, imageID: UUID(), capturedAt: Date())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try image.write(to: directory.appendingPathComponent(record.fileName), options: .atomic)
        values.removeAll { $0.id == id }; values.append(record)
        try JSONEncoder().encode(values).write(to: indexURL, options: .atomic)
        if let old { try? FileManager.default.removeItem(at: directory.appendingPathComponent(old.fileName)) }
        return record
    }
    public func image(for record: TabPreviewRecord) throws -> Data {
        let file = directory.appendingPathComponent(record.fileName)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 500_000 else { throw SnapshotError.invalidData }
        return try Data(contentsOf: file)
    }
    public func remove(id: UUID) throws {
        var values = try records(); let removed = values.filter { $0.id == id }; values.removeAll { $0.id == id }
        guard !removed.isEmpty else { return }
        try JSONEncoder().encode(values).write(to: indexURL, options: .atomic)
        for record in removed { try? FileManager.default.removeItem(at: directory.appendingPathComponent(record.fileName)) }
    }
}
