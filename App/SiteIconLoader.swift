import Foundation
import UIKit
import CryptoKit
import ImageIO

/// Contacts the favorite's origin and its declared icon, never a third-party favicon lookup service.
@MainActor
final class SiteIconLoader {
    static let shared = SiteIconLoader()
    private let memory = NSCache<NSString, UIImage>()
    private var requests: [String: Task<UIImage?, Never>] = [:]
    private var failures: [String: Date] = [:]
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PersonalBrowser/site-icons", isDirectory: true)
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")

    private func key(_ origin: URL) -> String { SHA256.hash(data: Data(origin.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() }
    func image(for url: URL, network: Bool) async -> UIImage? {
        guard let origin = SiteIconPolicy.origin(url) else { return nil }
        let id = key(origin)
        let file = directory.appendingPathComponent(id + ".png")
        let cached = memory.object(forKey: id as NSString) ?? UIImage(contentsOfFile: file.path)
        if let cached {
            memory.setObject(cached, forKey: id as NSString, cost: 192 * 192 * 4)
            // Cache successful icons across process restarts; no request on each home display.
            return cached
        }
        guard network, !testing else { return nil }
        if let failed = failures[id], Date().timeIntervalSince(failed) < 86400 { return nil }
        if let request = requests[id] { return await request.value }
        let request = Task { @MainActor () -> UIImage? in
            // Bound parallel origins rather than starting hundreds of favorite requests together.
            if active >= 4 { await withCheckedContinuation { waiters.append($0) } }
            else { active += 1 }
            defer {
                if waiters.isEmpty { active -= 1 }
                else { waiters.removeFirst().resume() }
            }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
            configuration.timeoutIntervalForRequest = 5; configuration.timeoutIntervalForResource = 15
            let session = URLSession(configuration: configuration, delegate: IconRedirectPolicy(origin: origin), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var candidates: [URL] = []
            if let (htmlData, final) = try? await Self.fetch(origin, limit: 256 * 1024, session: session, truncate: true),
               let html = String(data: htmlData, encoding: .utf8) ?? String(data: htmlData, encoding: .isoLatin1) {
                candidates = SiteIconPolicy.candidates(in: html, origin: final)
            }
            candidates += ["apple-touch-icon.png", "favicon.ico"].map { origin.appendingPathComponent($0) }
            for candidate in candidates.prefix(6) {
                guard SiteIconPolicy.permits(candidate, from: origin),
                      let (data, _) = try? await Self.fetch(candidate, limit: 512 * 1024, session: session) else { continue }
                let rendered = await Task.detached(priority: .utility) { () -> Data? in
                    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 192, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
                    let result = NSMutableData()
                    guard let target = CGImageDestinationCreateWithData(result as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
                    CGImageDestinationAddImage(target, image, nil)
                    return CGImageDestinationFinalize(target) ? result as Data : nil
                }.value
                guard let rendered, let image = UIImage(data: rendered) else { continue }
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? rendered.write(to: file, options: .atomic)
                memory.totalCostLimit = 12 * 1024 * 1024
                memory.setObject(image, forKey: id as NSString, cost: 192 * 192 * 4)
                return image
            }
            failures[id] = Date(); return nil
        }
        requests[id] = request
        let result = await request.value
        requests.removeValue(forKey: id)
        return result
    }

    nonisolated private static func fetch(_ url: URL, limit: Int, session: URLSession, truncate: Bool = false) async throws -> (Data, URL) {
        var request = URLRequest(url: url)
        request.setValue("image/*,text/html;q=0.8", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200, let final = response.url else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            if data.count == limit { if truncate { break }; throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return (data, final)
    }
}

private final class IconRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let origin: URL
    init(origin: URL) { self.origin = origin }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map { SiteIconPolicy.permits($0, from: origin) } == true ? request : nil)
    }
}
