import XCTest
import CryptoKit
@testable import BrowserCore

final class PasswordVaultTests: XCTestCase {
    private func record(_ password: String = "not-a-real-secret") throws -> PasswordRecord {
        try PasswordRecord(site: PasswordOrigin("https://example.com/login?a=1"), username: "日本語 user", password: password).validated()
    }
    func testSaveProposalsPreserveExistingMetadataRequireAccountAndCompareExactBytes() throws {
        var old = try record("old"); old.title = "Existing title"; old.notes = "Keep notes"
        var candidate = try record("new")
        XCTAssertEqual(try PasswordSavePolicy.proposal(candidate, records: [], passwordChange: false), .insert(candidate))
        var updated = old; updated.password = "new"
        XCTAssertEqual(try PasswordSavePolicy.proposal(candidate, records: [old], passwordChange: false), .update(updated))
        XCTAssertEqual(try PasswordSavePolicy.proposal(old, records: [old], passwordChange: false), .unchanged)
        candidate.username = ""
        XCTAssertEqual(try PasswordSavePolicy.proposal(candidate, records: [old], passwordChange: true), .update(updated))
        var second = old; second.id = UUID(); second.username = "second"
        XCTAssertEqual(try PasswordSavePolicy.proposal(candidate, records: [old, second], passwordChange: true), .chooseAccount)
        XCTAssertEqual(try PasswordSavePolicy.proposal(candidate, records: [old, second], passwordChange: true, accountID: old.id), .update(updated))
        var composed = old; composed.password = "\u{00e9}"
        var decomposed = old; decomposed.password = "e\u{0301}"
        XCTAssertEqual(try PasswordSavePolicy.proposal(decomposed, records: [composed], passwordChange: false), .update(decomposed))
        var otherSite = old; otherSite.site = try PasswordOrigin("https://example.com:444")
        XCTAssertEqual(try PasswordSavePolicy.proposal(old, records: [otherSite], passwordChange: false), .insert(old))
        candidate.password = ""
        XCTAssertThrowsError(try PasswordSavePolicy.proposal(candidate, records: [], passwordChange: false))
    }
    func testAutomaticFillRequiresOneExactAccountVisibleUntouchedFormAndUnlockedSession() throws {
        let value = try record(), site = value.site
        func candidate(_ records: [PasswordRecord] = [], enabled: Bool = true, unlocked: Bool = true, isPrivate: Bool = false, count: Int = 1, main: Bool = true, eligible: Bool = true) -> PasswordRecord? {
            PasswordAutomaticFillPolicy.candidate(records: records, site: site, enabled: enabled, unlocked: unlocked,
                isPrivate: isPrivate, formCount: count, isMainFrame: main, eligible: eligible)
        }
        XCTAssertEqual(candidate([value]), value)
        XCTAssertNil(candidate([value], enabled: false)); XCTAssertNil(candidate([value], unlocked: false))
        XCTAssertNil(candidate([value], isPrivate: true)); XCTAssertNil(candidate([value], count: 2))
        XCTAssertNil(candidate([value], main: false)); XCTAssertNil(candidate([value], eligible: false))
        var other = value; other.id = UUID(); other.username = "another-account"
        XCTAssertNil(candidate([value,other]))
        other.site = try PasswordOrigin("https://example.com:444")
        XCTAssertNil(candidate([other])); XCTAssertNil(candidate())
    }
    func testOriginIsExactAndRejectsUnsafeURLsAndMalformedDecodedHost() throws {
        let saved = try PasswordOrigin("https://EXAMPLE.com/login?q=secret#fragment")
        XCTAssertEqual(saved.display, "https://example.com")
        XCTAssertEqual(saved, try PasswordOrigin("https://example.com:443/another"))
        XCTAssertTrue(PasswordOrigin.mayFill(saved: saved, top: saved, frame: saved, trusted: true))
        for text in ["http://example.com", "https://sub.example.com", "https://example.com:444", "https://example.com.evil.test"] {
            let other = try PasswordOrigin(text)
            XCTAssertFalse(PasswordOrigin.mayFill(saved: saved, top: other, frame: other, trusted: true))
            XCTAssertFalse(PasswordOrigin.mayFill(saved: saved, top: saved, frame: other, trusted: true))
        }
        XCTAssertFalse(PasswordOrigin.mayFill(saved: saved, top: saved, frame: saved, trusted: false))
        for text in ["javascript:alert(1)", "file:///etc/test", "https://user:pass@example.com", "https://example.com:0", "https://example.com:65536"] {
            XCTAssertThrowsError(try PasswordOrigin(text))
        }
        let idn = try PasswordOrigin("https://例え.テスト/")
        XCTAssertEqual(try PasswordOrigin(idn.display), idn)
        for host in ["evil.test/path", "a b", ""] {
            let data = try JSONSerialization.data(withJSONObject: ["scheme":"https","host":host,"port":443])
            XCTAssertThrowsError(try JSONDecoder().decode(PasswordOrigin.self, from: data))
        }
    }
    func testSafariAndBraveCSVPreserveUnicodeQuotesNewlinesAndSecretWhitespace() throws {
        let safari = "\u{feff}Title,URL,Username,Password,Notes,OTPAuth\r\n名前,https://example.com/login,日本語,\"  A,B\"\"C\nD  \",メモ,ignored-code\r\nBad,javascript:alert(1),user,nope,,\r\n"
        let result = try PasswordCSV.parse(Data(safari.utf8))
        XCTAssertEqual(result.records.count, 1); XCTAssertEqual(result.skipped, 1); XCTAssertEqual(result.ignoredCodes, 1)
        XCTAssertEqual(result.records[0].password, "  A,B\"C\nD  ")
        XCTAssertEqual(result.records[0].username, "日本語")
        XCTAssertEqual(result.records[0].site.display, "https://example.com")
        let brave = "name,url,username,password,note\nTitle,https://example.org,user, secret ,note\n"
        XCTAssertEqual(try PasswordCSV.parse(Data(brave.utf8)).records[0].password, " secret ")
        var utf16 = Data([0xff,0xfe]); utf16.append(brave.data(using: .utf16LittleEndian)!)
        XCTAssertEqual(try PasswordCSV.parse(utf16).records[0].password, " secret ")
        for bad in ["url,username\nhttps://example.com,user", "url,username,password\nhttps://example.com,user,\"unterminated", "url,username,password\nhttps://example.com,user,\"secret\"altered", "url,username,password,password\nx,u,p,p"] {
            XCTAssertThrowsError(try PasswordCSV.parse(Data(bad.utf8)))
        }
        XCTAssertThrowsError(try PasswordCSV.parse(Data([0xff,0xff,0xff])))
        XCTAssertThrowsError(try PasswordCSV.parse(Data(repeating: 0x61, count: PasswordCSV.maximumBytes + 1)))
        XCTAssertThrowsError(try PasswordCSV.parse(Data((String(repeating: "column,", count: 100) + "end").utf8)))
    }
    func testImportDefaultsToPreservingExistingSecretsAndRequiresExplicitReplacement() throws {
        let old = try record(), new = try record("replacement")
        let kept = try PasswordImportResult.merged([old, new], into: [old], replace: false)
        XCTAssertEqual(kept.records, [old]); XCTAssertEqual(kept.duplicates, 1); XCTAssertEqual(kept.conflicts, 1)
        let replaced = try PasswordImportResult.merged([new], into: [old], replace: true)
        XCTAssertEqual(replaced.records[0].id, old.id); XCTAssertEqual(replaced.records[0].password, "replacement")
        XCTAssertThrowsError(try PasswordImportResult.merged([new], into: [old,old], replace: false))
        // Swift String equality is canonically equivalent; credential identity
        // and password replacement must nevertheless preserve the actual bytes.
        let composed = try record("\u{00e9}"), decomposed = try record("e\u{0301}")
        let changed = try PasswordImportResult.merged([decomposed], into: [composed], replace: true)
        XCTAssertEqual(Array(changed.records[0].password.utf8), Array(decomposed.password.utf8))
        XCTAssertEqual(changed.conflicts, 1)
        var first = old, second = old; first.username = "\u{00e9}"; second.username = "e\u{0301}"
        XCTAssertEqual(try PasswordImportResult.merged([second], into: [first], replace: false).records.count, 2)
    }
    func testVaultAuthenticatesCiphertextAndDoesNotExposePlaintext() throws {
        let value = try record(), key = SymmetricKey(size: .bits256)
        let data = try PasswordCryptography.seal([value], key: key)
        XCTAssertNil(data.range(of: Data(value.password.utf8)))
        XCTAssertNil(data.range(of: Data(value.username.utf8)))
        XCTAssertEqual(try PasswordCryptography.open(data, key: key), [value])
        XCTAssertNotEqual(data, try PasswordCryptography.seal([value], key: key), "Every write needs a new nonce")
        XCTAssertThrowsError(try PasswordCryptography.open(data, key: SymmetricKey(size: .bits256)))
        var changed = data; changed[changed.count-1] ^= 1
        XCTAssertThrowsError(try PasswordCryptography.open(changed, key: key))
        XCTAssertThrowsError(try PasswordCryptography.seal([value,value], key: key))
    }
    func testEncryptedBackupRoundTripWrongPassphraseAndMetadataTampering() throws {
        let value = try record(), passphrase = "long test-only passphrase 日本語"
        let data = try PasswordCryptography.backup([value], passphrase: passphrase)
        XCTAssertNil(data.range(of: Data(value.password.utf8)))
        XCTAssertEqual(try PasswordCryptography.restore(data, passphrase: passphrase), [value])
        XCTAssertThrowsError(try PasswordCryptography.restore(data, passphrase: "wrong test-only passphrase"))
        XCTAssertThrowsError(try PasswordCryptography.restore(data, passphrase: ""))
        XCTAssertThrowsError(try PasswordCryptography.backup([value], passphrase: "short"))
        var object = try JSONSerialization.jsonObject(with: data) as! [String:Any]
        object["iterations"] = 1
        XCTAssertThrowsError(try PasswordCryptography.restore(JSONSerialization.data(withJSONObject: object), passphrase: passphrase))
    }
    func testDedicatedZIPSelectionNeverChangesGeneralLibraryPasswordIsolation() throws {
        let data = Data(base64Encoded: "UEsDBBQAAAAAALugZ111qw6PTgAAAE4AAAAUAAAAU2FmYXJpL1Bhc3N3b3Jkcy5jc3ZUaXRsZSxVUkwsVXNlcm5hbWUsUGFzc3dvcmQKU2FmYXJpLGh0dHBzOi8vZXhhbXBsZS5jb20sdXNlcixub3QtYS1yZWFsLXNlY3JldApQSwMEFAAAAAAAu6BnXbQIsnIyAAAAMgAAABUAAABTYWZhcmkvQm9va21hcmtzLmh0bWw8REw+PEEgSFJFRj0iaHR0cHM6Ly9leGFtcGxlLm9yZyI+TGlicmFyeTwvQT48L0RMPlBLAQIUAxQAAAAAALugZ111qw6PTgAAAE4AAAAUAAAAAAAAAAAAAACAAQAAAABTYWZhcmkvUGFzc3dvcmRzLmNzdlBLAQIUAxQAAAAAALugZ120CLJyMgAAADIAAAAVAAAAAAAAAAAAAACAAYAAAABTYWZhcmkvQm9va21hcmtzLmh0bWxQSwUGAAAAAAIAAgCFAAAA5QAAAAAA")!
        let passwords = try BrowserArchive.passwordEntries(in: data)
        XCTAssertEqual(passwords.map(\.name), ["Safari/Passwords.csv"])
        XCTAssertEqual(try PasswordCSV.parse(BrowserArchive.contents(of: passwords[0])).records[0].password, "not-a-real-secret")
        XCTAssertEqual(try BrowserArchive.entries(in: data, kind: .bookmarks).map(\.name), ["Safari/Bookmarks.html"])
        #if canImport(Compression)
        let compressed = Data(base64Encoded: "UEsDBBQAAAAIALugZ111qw6PTAAAAE4AAAAUAAAAU2FmYXJpL1Bhc3N3b3Jkcy5jc3YNyrsNgDAMBcCeWRzSMwMFAjKAFR4iUn6yjWB8uPr2ZBkU1pmCQioX0MKqT5Nj2PhkSXSZdZ28x8ulZ4yxFbr/TLWZYyfg7BRRYMMHUEsDBBQAAAAIALugZ120CLJyMwAAADIAAAAVAAAAU2FmYXJpL0Jvb2ttYXJrcy5odG1ss3HxsbNxVPAIcnWzVcooKSkottLXT61IzC3ISdXLL0pXsvPJTCpKLKq00Xe0s9EHqgYAUEsBAhQDFAAAAAgAu6BnXXWrDo9MAAAATgAAABQAAAAAAAAAAAAAAIABAAAAAFNhZmFyaS9QYXNzd29yZHMuY3N2UEsBAhQDFAAAAAgAu6BnXbQIsnIzAAAAMgAAABUAAAAAAAAAAAAAAIABfgAAAFNhZmFyaS9Cb29rbWFya3MuaHRtbFBLBQYAAAAAAgACAIUAAADkAAAAAAA=")!
        let entry = try XCTUnwrap(BrowserArchive.passwordEntries(in: compressed).first)
        XCTAssertEqual(try PasswordCSV.parse(BrowserArchive.contents(of: entry)).records[0].username, "user")
        XCTAssertThrowsError(try BrowserArchive.verify(Data("tampered".utf8), entry: entry))
        #endif
    }
}
