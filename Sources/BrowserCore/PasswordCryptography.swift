import Foundation
import CryptoKit
#if canImport(CommonCrypto)
import CommonCrypto
#endif

public enum PasswordCryptography {
    public static let maximumPlaintext = 8 * 1024 * 1024
    private static let localContext = Data("PersonalBrowser.PasswordVault.v1".utf8)
    private static let backupContext = Data("PersonalBrowser.PasswordBackup.v1".utf8)
    public static func seal(_ records: [PasswordRecord], key: SymmetricKey) throws -> Data {
        let payload = try PasswordVaultPayload(records: records).validated()
        let data = try JSONEncoder().encode(payload)
        guard data.count <= maximumPlaintext else { throw PasswordVaultError.tooLarge }
        return try AES.GCM.seal(data, using: key, authenticating: localContext).combined!
    }
    public static func open(_ data: Data, key: SymmetricKey) throws -> [PasswordRecord] {
        guard data.count <= maximumPlaintext + 64 else { throw PasswordVaultError.tooLarge }
        do {
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: localContext)
            return try JSONDecoder().decode(PasswordVaultPayload.self, from: plain).validated().records
        } catch { throw PasswordVaultError.corrupted }
    }
    private struct Backup: Codable {
        var format = "PersonalBrowserPasswordBackup"
        var version = 1
        var iterations = 600000
        var salt: Data
        var sealed: Data
    }
    public static func backup(_ records: [PasswordRecord], passphrase: String) throws -> Data {
        guard passphrase.count >= 12, passphrase.utf8.count <= 1024 else { throw PasswordVaultError.backupPassword }
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        let key = try derive(passphrase, salt: salt)
        let plain = try JSONEncoder().encode(PasswordVaultPayload(records: records).validated())
        guard plain.count <= maximumPlaintext else { throw PasswordVaultError.tooLarge }
        let sealed = try AES.GCM.seal(plain, using: key, authenticating: backupContext).combined!
        return try JSONEncoder().encode(Backup(salt: salt, sealed: sealed))
    }
    public static func restore(_ data: Data, passphrase: String) throws -> [PasswordRecord] {
        guard data.count <= 12 * 1024 * 1024 else { throw PasswordVaultError.tooLarge }
        guard passphrase.count >= 12, passphrase.utf8.count <= 1024 else { throw PasswordVaultError.backupPassword }
        do {
            let file = try JSONDecoder().decode(Backup.self, from: data)
            guard file.format == "PersonalBrowserPasswordBackup", file.version == 1,
                  file.iterations == 600000, file.salt.count == 16,
                  file.sealed.count <= maximumPlaintext + 64 else { throw PasswordVaultError.backupPassword }
            let key = try derive(passphrase, salt: file.salt)
            let plain = try AES.GCM.open(AES.GCM.SealedBox(combined: file.sealed), using: key, authenticating: backupContext)
            return try JSONDecoder().decode(PasswordVaultPayload.self, from: plain).validated().records
        } catch { throw PasswordVaultError.backupPassword }
    }
    private static func derive(_ passphrase: String, salt: Data) throws -> SymmetricKey {
        #if canImport(CommonCrypto)
        var output = [UInt8](repeating: 0, count: 32)
        let bytes = Array(passphrase.utf8)
        let result = bytes.withUnsafeBytes { password in salt.withUnsafeBytes { salt in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), password.bindMemory(to: Int8.self).baseAddress!, bytes.count,
                salt.bindMemory(to: UInt8.self).baseAddress!, salt.count, CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), 600000, &output, 32)
        }}
        guard result == kCCSuccess else { throw PasswordVaultError.backupPassword }
        defer { output.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) } }
        return SymmetricKey(data: output)
        #else
        throw PasswordVaultError.unavailable
        #endif
    }
}
