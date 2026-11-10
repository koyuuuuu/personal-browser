import Foundation
import XCTest
@testable import BrowserCore

final class AddressTests: XCTestCase {
    func testBareDomainDefaultsToHTTPS() throws {
        XCTAssertEqual(try AddressResolver.resolve("example.com/page").absoluteString, "https://example.com/page")
    }
    func testExplicitHTTPIsPreserved() throws {
        XCTAssertEqual(try AddressResolver.resolve("http://example.com").scheme, "http")
    }
    func testHostWithPortIsNotTreatedAsScheme() throws {
        XCTAssertEqual(try AddressResolver.resolve("localhost:8080/page").port, 8080)
        XCTAssertEqual(try AddressResolver.resolve("example.com:8443").port, 8443)
    }
    func testJapaneseSearchAndQueryEscaping() throws {
        let url = try AddressResolver.resolve("日本語 & Swift+UI", engine: .google)
        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertTrue(url.absoluteString.contains("%2B"))
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "日本語 & Swift+UI")
    }
    func testWhitespaceAndEmpty() throws {
        XCTAssertThrowsError(try AddressResolver.resolve(" \n "))
        XCTAssertEqual(try AddressResolver.resolve("  example.com  ").host, "example.com")
    }
    func testExecutableAndLocalSchemesAreRejected() {
        for input in ["javascript:alert(1)", "file:///etc/hosts", "data:text/html,test", "myapp://host"] {
            XCTAssertThrowsError(try AddressResolver.resolve(input), input)
        }
    }
    func testInvalidExplicitAddressIsNotSearchedSilently() {
        XCTAssertThrowsError(try AddressResolver.resolve("https://"))
        XCTAssertThrowsError(try AddressResolver.resolve("https://example.com:99999"))
    }
    func testEmbeddedCredentialsAreRejected() {
        XCTAssertThrowsError(try AddressResolver.resolve("https://name:password@example.com/"))
    }
}

final class SnapshotTests: XCTestCase {
    func testPrivateTabsNeverEnterPersistedSession() throws {
        let regular = TabRecord(url: URL(string: "https://example.com"))
        let secret = TabRecord(url: URL(string: "https://private.example"))
        let session = SessionSnapshot.capture([
            TabState(record: regular, isPrivate: false),
            TabState(record: secret, isPrivate: true)
        ], selectedID: secret.id)
        XCTAssertEqual(session.tabs, [regular])
        XCTAssertEqual(session.selectedID, regular.id)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(session), as: UTF8.self).contains("private.example"))
    }
    func testPrivateVisitsDoNotChangeHistory() {
        var snapshot = BrowserSnapshot()
        snapshot.recordVisit(url: URL(string: "https://private.example")!, title: "Secret", isPrivate: true)
        XCTAssertTrue(snapshot.history.isEmpty)
    }
    func testRevisitsMoveToFrontAndHistoryIsBounded() {
        var snapshot = BrowserSnapshot()
        for index in 0..<1005 {
            snapshot.recordVisit(url: URL(string: "https://example.com/\(index)")!, title: "Page", isPrivate: false)
        }
        XCTAssertEqual(snapshot.history.count, 1000)
        let url = URL(string: "https://example.com/1000")!
        snapshot.recordVisit(url: url, title: "Updated", isPrivate: false)
        XCTAssertEqual(snapshot.history.first?.title, "Updated")
        XCTAssertEqual(snapshot.history.filter { $0.url == url }.count, 1)
    }
    func testUnsafeStoredURLIsRejected() {
        var snapshot = BrowserSnapshot()
        snapshot.bookmarks = [Bookmark(title: "Bad", url: URL(string: "javascript:alert(1)")!)]
        XCTAssertThrowsError(try snapshot.validated())
    }
    func testUnknownVersionIsRejected() {
        var snapshot = BrowserSnapshot()
        snapshot.schemaVersion = 2
        XCTAssertThrowsError(try snapshot.validated())
    }
    func testSettingsRemoveDuplicateToolbarActions() {
        var settings = BrowserSettings()
        settings.actions = [.tabs, .tabs, .back]
        XCTAssertEqual(settings.normalized().actions, [.tabs, .back])
    }
    func testSnapshotSurvivesAtomicSaveAndReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SnapshotStore(fileURL: directory.appendingPathComponent("browser.json"))
        XCTAssertEqual(try store.load(), BrowserSnapshot())
        var snapshot = BrowserSnapshot()
        snapshot.settings.toolbarPosition = .top
        snapshot.bookmarks = [Bookmark(title: "Example", url: URL(string: "https://example.com")!)]
        try store.save(snapshot)
        XCTAssertEqual(try store.load(), snapshot)
    }
    func testCorruptSaveIsReportedAndNotOverwrittenByLoad() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let badData = Data("not JSON".utf8)
        try badData.write(to: file)
        XCTAssertThrowsError(try SnapshotStore(fileURL: file).load())
        XCTAssertEqual(try Data(contentsOf: file), badData)
    }
}

final class VideoOrientationTests: XCTestCase {
    func testAspectAndGravityDoNotConfuseFlatOrDiagonalPhoneWithRotation() {
        XCTAssertEqual(VideoTilt.gravity(x: -0.95, y: 0.1, z: 0.1), .landscapeRight)
        XCTAssertEqual(VideoTilt.gravity(x: 0.95, y: 0.1, z: 0.1), .landscapeLeft)
        XCTAssertEqual(VideoTilt.gravity(x: 0, y: -1, z: 0), .portrait)
        XCTAssertNil(VideoTilt.gravity(x: 0.1, y: 0.1, z: -0.99))
        XCTAssertNil(VideoTilt.gravity(x: 0.7, y: -0.7, z: 0))
        XCTAssertNil(VideoTilt.gravity(x: .nan, y: 0, z: 0))
        XCTAssertEqual(VideoTilt.forVideo(width: 1920, height: 1080, tilt: .portrait), .landscapeRight)
        XCTAssertEqual(VideoTilt.forVideo(width: 1080, height: 1920, tilt: .landscapeLeft), .portrait)
        XCTAssertEqual(VideoTilt.forVideo(width: 1080, height: 1080, tilt: .landscapeLeft), .portrait)
        XCTAssertNil(VideoTilt.forVideo(width: 0, height: 0, tilt: .portrait))
    }
    func testGridWidthsSurviveRepeatedRotationsAndRespectInsets() {
        for count in 1...4 {
            for viewport in [390.0, 844, 390, 844, 390] {
                let insets = viewport > 400 ? 94.0 : 0
                let width = TabGridMetrics.width(viewport: viewport, horizontalInsets: insets, columns: count)
                XCTAssertLessThanOrEqual(width * Double(count) + Double(count - 1) * 16 + 32 + insets, viewport)
                XCTAssertGreaterThan(width, 40)
            }
        }
        XCTAssertEqual(TabGridMetrics.width(viewport: 390, horizontalInsets: 0, columns: 2), 171)
    }
}
