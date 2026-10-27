import Foundation
import Combine
import CryptoKit
import WebKit
import UIKit

/// Only WebKit rule data is downloaded; browsing URLs are never sent to a filtering service.
@MainActor
final class ContentBlocking: ObservableObject {
    static let shared = ContentBlocking()
    static let delivery = URL(string: "https://github.com/koyuuuuu/personal-browser-distribution/releases/download/filter-data-v1/")!
    @Published private(set) var status = "広告フィルターを準備中…"
    @Published private(set) var preferences = BlockingPreferences()
    @Published private(set) var configurationID = UUID()
    @Published private(set) var updating = false
    @Published private(set) var generatedAt = ""
    @Published private(set) var ruleCount = 0
    private var tasks: [String: Task<[WKContentRuleList], Error>] = [:]
    private let directory: URL
    private let bundleDirectory: URL
    private var manifest: BlockingManifest?
    private var activeDirectory: URL
    private let testing = ProcessInfo.processInfo.arguments.contains("--ui-testing")
    private static let preferenceKey = "blocking-preferences-v1"
    private var foregroundObserver: AnyCancellable?

    private init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PersonalBrowser/filter-data", isDirectory: true)
        bundleDirectory = Bundle.main.resourceURL!.appendingPathComponent("FilterResources", isDirectory: true)
        activeDirectory = bundleDirectory
        if let data = UserDefaults.standard.data(forKey: Self.preferenceKey), let value = try? JSONDecoder().decode(BlockingPreferences.self, from: data) { preferences = value }
        if testing { preferences = BlockingPreferences() }
        if !testing, let cached = Self.readManifest(directory.appendingPathComponent("manifest.json")) {
            manifest = cached; activeDirectory = directory.appendingPathComponent(cached.revision, isDirectory: true)
        } else { manifest = Self.readManifest(bundleDirectory.appendingPathComponent("manifest.json")) }
        generatedAt = manifest?.generatedAt ?? ""
        foregroundObserver = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification).sink { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkForUpdates() }
        }
    }

    private static func readManifest(_ url: URL) -> BlockingManifest? {
        guard let data = try? Data(contentsOf: url), data.count <= 512 * 1024,
              let value = try? JSONDecoder().decode(BlockingManifest.self, from: data) else { return nil }
        return try? value.validated()
    }

    func set<Value>(_ key: WritableKeyPath<BlockingPreferences, Value>, _ value: Value) {
        preferences[keyPath: key] = value
        if !testing, let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: Self.preferenceKey) }
        configurationID = UUID()
    }

    func rules() async -> [WKContentRuleList] {
        guard let manifest else { status = "内蔵フィルターを読み込めませんでした"; return [] }
        do {
            let result = try await prepared(manifest, at: activeDirectory, preferences: preferences)
            status = preferences.strength == .standard ? "標準フィルターを適用できます" : "強力フィルターを適用できます"
            ruleCount = manifest.files(for: preferences).reduce(0) { $0 + $1.count }
            return result
        } catch {
            if activeDirectory != bundleDirectory, let baseline = Self.readManifest(bundleDirectory.appendingPathComponent("manifest.json")),
               let result = try? await prepared(baseline, at: bundleDirectory, preferences: preferences) {
                status = "更新版を適用できないため内蔵フィルターを使用中"; return result
            }
            status = "広告フィルターの準備に失敗しました。再度お試しください。"
            return []
        }
    }

    private func prepared(_ manifest: BlockingManifest, at root: URL, preferences: BlockingPreferences) async throws -> [WKContentRuleList] {
        let selected = manifest.files(for: preferences)
        let key = manifest.revision + preferences.strength.rawValue + String(preferences.cosmetic)
        if let task = tasks[key] { return try await task.value }
        let task = Task { @MainActor () throws -> [WKContentRuleList] in
            var output: [WKContentRuleList] = []
            for file in selected {
                let identifier = "PB-filter-v1-" + file.sha256
                let cached: WKContentRuleList? = await withCheckedContinuation { continuation in
                    WKContentRuleListStore.default().lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                        continuation.resume(returning: list)
                    }
                }
                if let cached {
                    output.append(cached); continue
                }
                let json = try await Task.detached(priority: .utility) {
                    let data = try Data(contentsOf: root.appendingPathComponent(file.name))
                    guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw BlockingDataError.invalid }
                    try file.validate(data)
                    guard let json = String(data: data, encoding: .utf8) else { throw BlockingDataError.invalid }
                    return json
                }.value
                let list: WKContentRuleList = try await withCheckedThrowingContinuation { continuation in
                    WKContentRuleListStore.default().compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                        if let error { continuation.resume(throwing: error) }
                        else if let list { continuation.resume(returning: list) }
                        else { continuation.resume(throwing: BlockingDataError.invalid) }
                    }
                }
                output.append(list)
            }
            return output
        }
        tasks[key] = task
        do { return try await task.value }
        catch { tasks.removeValue(forKey: key); throw error }
    }

    func checkForUpdates(force: Bool = false) async {
        guard !testing, !updating, force || preferences.automaticUpdates else { return }
        let last = UserDefaults.standard.double(forKey: "blocking-last-check-v1")
        guard force || Date().timeIntervalSince1970 - last >= 86400 else { return }
        updating = true; defer { updating = false }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "blocking-last-check-v1")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            let raw = try await Self.fetch(Self.delivery.appendingPathComponent("manifest.json"), limit: 512 * 1024, session: session)
            let candidate = try JSONDecoder().decode(BlockingManifest.self, from: raw).validated()
            if candidate.revision == manifest?.revision { status = "フィルターは最新です"; return }
            let staging = directory.appendingPathComponent("staging-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            var files: [String: BlockingRuleFile] = [:]
            for profile in candidate.profiles.values { for file in profile { files[file.name] = file } }
            guard files.values.reduce(0, { $0 + $1.size }) <= 64 * 1024 * 1024 else { throw BlockingDataError.invalid }
            for file in files.values {
                let data = try await Self.fetch(Self.delivery.appendingPathComponent(file.name), limit: file.size, session: session)
                guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else { throw BlockingDataError.invalid }
                try await Task.detached(priority: .utility) { try file.validate(data) }.value
                try data.write(to: staging.appendingPathComponent(file.name), options: .atomic)
            }
            _ = try await prepared(candidate, at: staging, preferences: preferences)
            let final = directory.appendingPathComponent(candidate.revision, isDirectory: true)
            if FileManager.default.fileExists(atPath: final.path) { try FileManager.default.removeItem(at: final) }
            try FileManager.default.moveItem(at: staging, to: final)
            // Switch the active pointer only after download, hash validation and WebKit compilation succeed.
            try raw.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
            manifest = candidate; activeDirectory = final; generatedAt = candidate.generatedAt
            configurationID = UUID(); status = "フィルターを更新しました"
            let previous = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.lastPathComponent.count == 64 && $0 != final }
                .sorted { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
            for old in previous.dropFirst() { try? FileManager.default.removeItem(at: old) }
        } catch { status = "更新できませんでした。現在のフィルターを継続使用します。" }
    }

    nonisolated private static func fetch(_ url: URL, limit: Int, session: URLSession) async throws -> Data {
        var request = URLRequest(url: url); request.cachePolicy = .reloadIgnoringLocalCacheData
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw BlockingDataError.invalid }
        var data = Data()
        for try await byte in bytes { data.append(byte); if data.count > limit { throw BlockingDataError.invalid } }
        return data
    }

    var sourceArchiveURL: URL? { manifest.map { Self.delivery.appendingPathComponent($0.sourceArchive) } }
    var notices: String {
        ["FilterNotices", "GPL-3.0", "MPL-2.0"].compactMap {
            try? String(contentsOf: bundleDirectory.appendingPathComponent($0 + ".txt"), encoding: .utf8)
        }.joined(separator: "\n\n")
    }
}
