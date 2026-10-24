import Foundation
import XCTest
@testable import BrowserCore

final class PresentationTests: XCTestCase {
    func testLandscapeStartsHiddenAndReverseScrollRevealsCompactBar() {
        var state = ChromeVisibility(); XCTAssertTrue(state.visible)
        state.setLandscape(true); XCTAssertFalse(state.visible)
        state.scroll(delta: 5); state.scroll(delta: -5); XCTAssertFalse(state.visible)
        state.scroll(delta: -20); XCTAssertTrue(state.visible)
        state.scroll(delta: 40); XCTAssertFalse(state.visible)
        state.reveal(); state.setLandscape(false); XCTAssertTrue(state.visible)
        state.hide(); state.setLandscape(true); state.setLandscape(false); XCTAssertFalse(state.visible)
    }
    func testNextTabAtEndCreatesOnlyWithinLimitAndPreviousDoesNot() {
        XCTAssertEqual(TabNavigation.destination(current: 2, count: 3, towardNext: true), .create)
        XCTAssertEqual(TabNavigation.destination(current: 0, count: 3, towardNext: false), .none)
        XCTAssertEqual(TabNavigation.destination(current: 1, count: 3, towardNext: false), .existing(0))
        XCTAssertEqual(TabNavigation.destination(current: 499, count: 500, towardNext: true), .none)
    }
    func testNewPresentationFileDecodesDefaultsAndBoundsControls() throws {
        XCTAssertEqual(try JSONDecoder().decode(PresentationPreferences.self, from: Data("{}".utf8)), PresentationPreferences())
        var prefs = PresentationPreferences(); prefs.pageZoom = 100; prefs.tabColumns = 500
        prefs.backgroundZoom = -1; prefs.backgroundHorizontalOffset = 5
        prefs.addressLeft = [.tabs, .tabs, .newTab]
        let normalized = prefs.normalized()
        XCTAssertEqual(normalized.pageZoom, 2); XCTAssertEqual(normalized.tabColumns, 4)
        XCTAssertEqual(normalized.backgroundZoom, 1); XCTAssertEqual(normalized.backgroundHorizontalOffset, 1)
        XCTAssertEqual(normalized.addressLeft, [.tabs, .newTab])
    }
    func testImageCroppingCoversViewportAndStaysWithinItsBounds() {
        var p = PresentationPreferences(); p.backgroundZoom = 1.5
        for x in [-1.0, 0, 1] {
            for y in [-1.0, 0, 1] {
                p.backgroundHorizontalOffset = x; p.backgroundVerticalOffset = y
                let result = BackgroundPlacement.calculate(imageWidth: 1800, imageHeight: 1200, viewportWidth: 390, viewportHeight: 700, preferences: p)
                XCTAssertLessThanOrEqual(result.x - result.width / 2, 0.0001)
                XCTAssertGreaterThanOrEqual(result.x + result.width / 2, 389.9999)
                XCTAssertLessThanOrEqual(result.y - result.height / 2, 0.0001)
                XCTAssertGreaterThanOrEqual(result.y + result.height / 2, 699.9999)
            }
        }
    }
    func testPreviewsSurviveStoreRecreationAndReplaceOnlyTheirOwnGeneration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TabPreviewStore(directory: folder), id = UUID(), url = URL(string: "https://example.com")!
        let first = try XCTUnwrap(store.save(id: id, url: url, title: "First", image: Data("frame1".utf8), isPrivate: false))
        let recreated = TabPreviewStore(directory: folder)
        XCTAssertEqual(try recreated.image(for: XCTUnwrap(recreated.records().first)), Data("frame1".utf8))
        let second = try XCTUnwrap(recreated.save(id: id, url: url, title: "Latest", image: Data("frame2".utf8), isPrivate: false))
        XCTAssertEqual(try store.records().first?.title, "Latest")
        XCTAssertEqual(try store.image(for: second), Data("frame2".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent(first.fileName).path))
        try store.remove(id: id); XCTAssertTrue(try store.records().isEmpty)
    }
    func testPrivatePreviewsNeverTouchDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TabPreviewStore(directory: folder)
        XCTAssertNil(try store.save(id: UUID(), url: URL(string: "https://private.example")!, title: "Secret", image: Data("image".utf8), isPrivate: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
    func testCertificatePermissionIsPinnedToOriginPortAndExactCertificate() throws {
        var preferences = ConnectionPreferences()
        let fingerprint = String(repeating: "a", count: 64)
        try preferences.rememberCertificate(origin: "https://192.168.1.120:3000", fingerprint: fingerprint)
        XCTAssertTrue(preferences.trusts(origin: "https://192.168.1.120:3000", fingerprint: fingerprint))
        XCTAssertFalse(preferences.trusts(origin: "https://192.168.1.120:3001", fingerprint: fingerprint))
        XCTAssertFalse(preferences.trusts(origin: "https://192.168.1.121:3000", fingerprint: fingerprint))
        XCTAssertFalse(preferences.trusts(origin: "https://192.168.1.120:3000", fingerprint: String(repeating: "b", count: 64)))
        XCTAssertThrowsError(try preferences.rememberCertificate(origin: "https://example.com", fingerprint: "invalid"))
    }
    func testHTTPFallbackIsLimitedToLocalNetworkAndRequiresSavedDecision() {
        let local = URL(string: "https://192.168.1.120:3000/tool?q=one&x=2")!
        var p = ConnectionPreferences()
        XCTAssertEqual(ConnectionSecurity.preferredURL(local, preferences: p), local)
        p.httpOrigins = [ConnectionSecurity.origin(local)!]
        XCTAssertEqual(ConnectionSecurity.preferredURL(local, preferences: p).absoluteString, "http://192.168.1.120:3000/tool?q=one&x=2")
        XCTAssertNil(ConnectionSecurity.httpAlternative(URL(string: "https://example.com")!))
        XCTAssertNil(ConnectionSecurity.httpAlternative(URL(string: "https://172.32.1.1")!))
        XCTAssertNil(ConnectionSecurity.httpAlternative(URL(string: "https://user:pass@192.168.1.120")!))
        XCTAssertNotNil(ConnectionSecurity.httpAlternative(URL(string: "https://127.0.0.1:3000")!))
    }
}
