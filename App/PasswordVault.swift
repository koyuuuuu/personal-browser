import Combine
import CryptoKit
@preconcurrency import LocalAuthentication
import Security
import UIKit

@MainActor
final class PasswordVault: ObservableObject {
    static let shared = PasswordVault()
    @Published private(set) var records: [PasswordRecord] = []
    @Published private(set) var unlocked = false
    @Published private(set) var busy = false
    @Published private(set) var needsRecovery = false
    @Published private(set) var revision = UUID()
    @Published private(set) var showInputButton = UserDefaults.standard.object(forKey: "password-vault.show-input.v1") as? Bool ?? true
    @Published private(set) var allowPrivateFill = UserDefaults.standard.bool(forKey: "password-vault.private-fill.v1")
    @Published private(set) var lockSeconds = UserDefaults.standard.object(forKey: "password-vault.lock-seconds.v1") as? Int ?? 60
    private var key: SymmetricKey?
    private var keyID: UUID?
    private var context: LAContext?
    private var generation = UUID()
    private var timer: Timer?
    private var expiresAt: Date?
    private var backgroundObserver: AnyCancellable?
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("vault-v1.json") }
    nonisolated private static let service = "local.personalbrowser.password-vault.v1"
    private struct Envelope: Codable { var version = 1; var keyID: UUID; var sealed: Data }
    static var fixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--ui-testing") && ProcessInfo.processInfo.arguments.contains("--ui-password-fixture")
        #else
        false
        #endif
    }
    private init() {
        let manager = FileManager.default
        if Self.fixture {
            directory = manager.temporaryDirectory.appendingPathComponent("PasswordVaultUITests", isDirectory: true)
            if !ProcessInfo.processInfo.arguments.contains("--ui-keep-data") { try? manager.removeItem(at: directory) }
        } else {
            directory = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PersonalBrowserPasswordVault", isDirectory: true)
        }
        backgroundObserver = NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification).sink { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
    }
    func setShowInput(_ value: Bool) { showInputButton = value; UserDefaults.standard.set(value, forKey: "password-vault.show-input.v1") }
    func setPrivateFill(_ value: Bool) { allowPrivateFill = value; UserDefaults.standard.set(value, forKey: "password-vault.private-fill.v1") }
    func setLockSeconds(_ value: Int) {
        lockSeconds = [30,60,300].contains(value) ? value : 60
        UserDefaults.standard.set(lockSeconds, forKey: "password-vault.lock-seconds.v1"); if unlocked { armTimer() }
    }
    func lock() {
        generation = UUID(); timer?.invalidate(); timer = nil; expiresAt = nil
        context?.invalidate(); context = nil; key = nil; keyID = nil; records = []; unlocked = false; revision = UUID()
    }
    func unlock() async throws {
        if unlocked { try requireUnlocked(); return }
        guard !busy else { throw PasswordVaultError.locked }
        busy = true; defer { busy = false }
        let token = generation
        let auth = try await authenticate()
        guard generation == token else { throw PasswordVaultError.locked }
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                let data = try Self.readLimited(file, limit: 12 * 1024 * 1024)
                let envelope = try JSONDecoder().decode(Envelope.self, from: data)
                guard envelope.version == 1 else { throw PasswordVaultError.corrupted }
                let secret = try await Self.readKey(envelope.keyID, context: auth)
                guard generation == token else { throw PasswordVaultError.locked }
                let values = try PasswordCryptography.open(envelope.sealed, key: secret)
                key = secret; keyID = envelope.keyID; records = values
            } else {
                let id = UUID(), secret = Self.newKey()
                try Self.addKey(secret, id: id)
                do { try write([], key: secret, id: id) }
                catch { Self.deleteKey(id, context: auth); throw error }
                key = secret; keyID = id; records = []
            }
            needsRecovery = false; unlocked = true; revision = UUID(); armTimer()
        } catch PasswordVaultError.locked { throw PasswordVaultError.locked }
        catch PasswordVaultError.authentication { throw PasswordVaultError.authentication }
        catch {
            guard generation == token else { throw PasswordVaultError.locked }
            needsRecovery = true; throw PasswordVaultError.corrupted
        }
    }
    private func authenticate() async throws -> LAContext {
        let auth = LAContext(); context = auth
        #if DEBUG
        if Self.fixture { return auth }
        #endif
        guard auth.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { throw PasswordVaultError.unavailable }
        do {
            guard try await auth.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "このブラウザのパスワード保管庫を開きます") else { throw PasswordVaultError.authentication }
        } catch { throw PasswordVaultError.authentication }
        return auth
    }
    private func armTimer() {
        timer?.invalidate()
        expiresAt = Date().addingTimeInterval(TimeInterval(lockSeconds))
        timer = Timer(timeInterval: TimeInterval(lockSeconds), repeats: false) { [weak self] _ in
            Task { @MainActor in self?.lock() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func requireUnlocked() throws {
        guard unlocked, let expiresAt, Date() < expiresAt else { lock(); throw PasswordVaultError.locked }
    }
    func save(_ record: PasswordRecord) throws {
        try requireUnlocked()
        let value = try record.validated()
        var result = records
        guard !result.contains(where: { $0.id != value.id && $0.accountKey == value.accountKey }) else { throw PasswordVaultError.invalidRecord }
        if let index = result.firstIndex(where: { $0.id == value.id }) { result[index] = value }
        else { result.append(value) }
        try commit(result)
    }
    func delete(_ record: PasswordRecord) throws { try commit(records.filter { $0.id != record.id }) }
    func importRecords(_ values: [PasswordRecord], replace: Bool) throws {
        let result = try PasswordImportResult.merged(values, into: records, replace: replace)
        try commit(result.records)
    }
    private func commit(_ values: [PasswordRecord]) throws {
        try requireUnlocked()
        guard let key, let keyID else { throw PasswordVaultError.locked }
        try write(values, key: key, id: keyID); records = values; revision = UUID(); armTimer()
    }
    private func write(_ values: [PasswordRecord], key: SymmetricKey, id: UUID) throws {
        let sealed = try PasswordCryptography.seal(values, key: key)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        var root = directory; var options = URLResourceValues(); options.isExcludedFromBackup = true; try root.setResourceValues(options)
        let data = try JSONEncoder().encode(Envelope(keyID: id, sealed: sealed))
        try data.write(to: file, options: [.atomic, .completeFileProtection])
    }
    /// Explicit user-confirmed replacement from an encrypted backup. New key
    /// and encrypted file are prepared before replacing the old file pointer.
    func replaceFromBackup(_ values: [PasswordRecord]) async throws {
        guard !busy else { throw PasswordVaultError.locked }
        busy = true; defer { busy = false }
        let token = generation, auth = try await authenticate()
        guard generation == token else { throw PasswordVaultError.locked }
        let id = UUID(), secret = Self.newKey()
        try Self.addKey(secret, id: id)
        do { try write(values, key: secret, id: id) }
        catch { Self.deleteKey(id, context: auth); throw error }
        // Old items are intentionally not deleted on replacement. Their UUIDs
        // are no longer referenced, preserving recovery from interrupted writes.
        key = secret; keyID = id; records = values; needsRecovery = false; unlocked = true; revision = UUID(); armTimer()
    }
    private static func newKey() -> SymmetricKey {
        #if DEBUG
        if fixture { return SymmetricKey(data: Data(repeating: 0x42, count: 32)) }
        #endif
        return SymmetricKey(size: .bits256)
    }
    private static func addKey(_ key: SymmetricKey, id: UUID) throws {
        #if DEBUG
        if fixture { return }
        #endif
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil) else { throw PasswordVaultError.unavailable }
        let data = key.withUnsafeBytes { Data($0) }
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: id.uuidString,
            kSecAttrAccessControl: access, kSecAttrSynchronizable: false, kSecValueData: data] as CFDictionary, nil)
        guard status == errSecSuccess else { throw PasswordVaultError.unavailable }
    }
    nonisolated private static func readKey(_ id: UUID, context: LAContext) async throws -> SymmetricKey {
        #if DEBUG
        if await fixture { return SymmetricKey(data: Data(repeating: 0x42, count: 32)) }
        #endif
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: CFTypeRef?
                let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service,
                    kSecAttrAccount: id.uuidString, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
                    kSecUseAuthenticationContext: context] as CFDictionary, &result)
                guard status == errSecSuccess, var data = result as? Data, data.count == 32 else {
                    continuation.resume(throwing: [errSecUserCanceled, errSecAuthFailed, errSecInteractionNotAllowed].contains(status) ? PasswordVaultError.authentication : PasswordVaultError.corrupted); return
                }
                let key = SymmetricKey(data: data); data.resetBytes(in: data.startIndex..<data.endIndex)
                continuation.resume(returning: key)
            }
        }
    }
    private static func deleteKey(_ id: UUID, context: LAContext) {
        #if DEBUG
        if fixture { return }
        #endif
        SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: id.uuidString,
            kSecUseAuthenticationContext: context] as CFDictionary)
    }
    nonisolated static func readLimited(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw PasswordVaultError.tooLarge }
        return data
    }
}
