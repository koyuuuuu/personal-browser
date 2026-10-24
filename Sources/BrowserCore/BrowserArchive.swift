import Foundation
#if canImport(Compression)
import Compression
#endif

/// ZIP directory reader; extracts selected in-memory entries only, never paths.
/// Password files in a Safari export are skipped before decompression.
public enum BrowserArchive {
    public struct Entry: Sendable {
        public let name: String
        public let method: Int
        public let compressed: Data
        public let size: Int
        public let crc32: UInt32
    }
    public static func entries(in data: Data, kind: LibraryImportKind) throws -> [Entry] {
        func number(_ offset: Int, _ bytes: Int) throws -> UInt32 {
            guard offset >= 0, bytes <= 4, offset + bytes <= data.count else { throw LibraryTransferError.malformed }
            return (0..<bytes).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 22, data.count <= 20 * 1024 * 1024 else { throw LibraryTransferError.tooLarge }
        var end: Int?
        for i in stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1) {
            if try number(i, 4) == 0x06054b50, i + 22 + Int(try number(i + 20, 2)) == data.count { end = i; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw LibraryTransferError.malformed }
        let count = Int(try number(end + 10, 2)), offset = Int(try number(end + 16, 4))
        guard count < 10_000, count != 0xffff, offset < data.count else { throw LibraryTransferError.tooLarge }
        var cursor = offset, total = 0, result: [Entry] = []
        for _ in 0..<count {
            guard try number(cursor, 4) == 0x02014b50 else { throw LibraryTransferError.malformed }
            let flags = try number(cursor + 8, 2), method = Int(try number(cursor + 10, 2))
            let checksum = try number(cursor + 16, 4), compressed = Int(try number(cursor + 20, 4)), size = Int(try number(cursor + 24, 4))
            let nameLength = Int(try number(cursor + 28, 2)), extra = Int(try number(cursor + 30, 2)), comment = Int(try number(cursor + 32, 2))
            let local = Int(try number(cursor + 42, 4)), next = cursor + 46 + nameLength + extra + comment
            guard next <= data.count, let name = String(data: data[(cursor + 46)..<(cursor + 46 + nameLength)], encoding: .utf8) else { throw LibraryTransferError.malformed }
            cursor = next
            let lower = name.lowercased(), ext = URL(fileURLWithPath: name).pathExtension.lowercased()
            if lower.contains("password") || lower.contains("パスワード") || lower.contains("credential") || lower.contains("__macosx") { continue }
            guard ["html", "htm", "csv", "json"].contains(ext) else { continue }
            if kind == .history && (ext == "html" || ext == "htm" || lower.contains("bookmark")) { continue }
            if kind != .history && (lower.contains("history") || lower.contains("履歴")) { continue }
            guard flags & 1 == 0, [0, 8].contains(method), size <= 20 * 1024 * 1024 else { throw LibraryTransferError.unsupported }
            total += size; guard total <= 20 * 1024 * 1024 else { throw LibraryTransferError.tooLarge }
            guard try number(local, 4) == 0x04034b50 else { throw LibraryTransferError.malformed }
            let start = local + 30 + Int(try number(local + 26, 2)) + Int(try number(local + 28, 2))
            guard start >= 0, start + compressed <= data.count else { throw LibraryTransferError.malformed }
            result.append(Entry(name: name, method: method, compressed: Data(data[start..<(start + compressed)]), size: size, crc32: checksum))
        }
        return result
    }
    public static func contents(of entry: Entry) throws -> Data {
        let data: Data
        if entry.method == 0 { data = entry.compressed }
        else {
            #if canImport(Compression)
            if entry.size == 0 { try verify(Data(), entry: entry); return Data() }
            guard !entry.compressed.isEmpty else { throw LibraryTransferError.malformed }
            var output = [UInt8](repeating: 0, count: entry.size + 1)
            let decoded = entry.compressed.withUnsafeBytes { source in
                output.withUnsafeMutableBufferPointer { destination in
                    compression_decode_buffer(destination.baseAddress!, destination.count, source.bindMemory(to: UInt8.self).baseAddress!, entry.compressed.count, nil, COMPRESSION_ZLIB)
                }
            }
            guard decoded == entry.size else { throw LibraryTransferError.malformed }
            data = Data(output.prefix(decoded))
            #else
            throw LibraryTransferError.unsupported
            #endif
        }
        try verify(data, entry: entry)
        return data
    }
    public static func verify(_ data: Data, entry: Entry) throws {
        var crc: UInt32 = 0xffffffff
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 255)] ^ (crc >> 8) }
        guard data.count == entry.size, (crc ^ 0xffffffff) == entry.crc32 else { throw LibraryTransferError.malformed }
    }
    private static let crcTable: [UInt32] = (0..<256).map { index in
        var value = UInt32(index)
        for _ in 0..<8 { value = value & 1 != 0 ? 0xedb88320 ^ (value >> 1) : value >> 1 }
        return value
    }
}
