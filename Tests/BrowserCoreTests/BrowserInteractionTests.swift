import XCTest
@testable import BrowserCore

final class BrowserInteractionTests: XCTestCase {
    func testHistoryGroupsAtNoonInLocalTimeIncludingDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let format = ISO8601DateFormatter()
        let dates = ["2026-03-08T05:30:00Z", "2026-03-08T15:59:59Z", "2026-03-08T16:00:00Z", "2026-03-09T03:30:00Z", "2026-03-09T04:30:00Z"]
        let entries = dates.enumerated().map { i, date in HistoryEntry(title: "\(i)", url: URL(string: "https://example.com/\(i)")!, visitedAt: format.date(from: date)!) }
        let periods = HistoryPresentation.periods(entries, calendar: calendar)
        XCTAssertEqual(periods.count, 3)
        XCTAssertEqual(periods.map(\.afternoon), [false, true, false])
        XCTAssertEqual(periods.map { $0.entries.count }, [1, 2, 2])
        XCTAssertEqual(periods[1].entries.map(\.title), ["3", "2"])
    }
    func testAddressSuggestionsMatchTitleOrPartialURLAndDeduplicate() {
        let a = HistoryEntry(title: "日本語の動画", url: URL(string: "https://example.com/watch")!, visitedAt: Date(timeIntervalSince1970: 2))
        let b = HistoryEntry(title: "Video archive", url: URL(string: "https://example.org/VIDEO")!, visitedAt: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(HistoryPresentation.suggestions("動画", history: [b, a]).map(\.url), [a.url])
        XCTAssertEqual(HistoryPresentation.suggestions("video", history: [b, b, a]).count, 1)
        XCTAssertEqual(HistoryPresentation.suggestions("example", history: [b, a], limit: 1).first?.url, a.url)
        XCTAssertTrue(HistoryPresentation.suggestions("  ", history: [a]).isEmpty)
    }
    func testPortraitHidesOnForwardFingerMovementAndRevealsOnReverse() {
        var state = ChromeVisibility()
        state.scroll(delta: 35); XCTAssertFalse(state.visible)
        state.scroll(delta: 10); XCTAssertFalse(state.visible)
        state.scroll(delta: -5); XCTAssertFalse(state.visible)
        state.scroll(delta: -15); XCTAssertTrue(state.visible)
    }
    func testZoomMovesExactlyFivePercentagePointsAndKeepsLegacySettingsReadable() throws {
        var zoom = 1.0
        for _ in 0..<3 { zoom = PageMagnification.step(zoom, increase: true) }
        XCTAssertEqual(zoom, 1.15, accuracy: 0.000001)
        XCTAssertEqual(PageMagnification.step(zoom, increase: false), 1.10, accuracy: 0.000001)
        XCTAssertEqual(PageMagnification.step(2, increase: true), 2)
        XCTAssertEqual(PageMagnification.step(0.75, increase: false), 0.75)
        var controls = ToolbarPreferences(); controls.main = [.tabs, .zoomIn]; controls.left = [.zoomOut]
        XCTAssertEqual(try JSONDecoder().decode(ToolbarPreferences.self, from: JSONEncoder().encode(controls)), controls)
        XCTAssertEqual(try JSONDecoder().decode(BrowserSnapshot.self, from: JSONEncoder().encode(BrowserSnapshot())).schemaVersion, 1)
    }
    func testSafariNumericEntitiesPreserveJapaneseEmojiFoldersAndURLQuery() throws {
        let html = "<DL><DT><H3>&#12362;&#27671;&#12395;&#20837;&#12426;</H3><DL><A HREF='https://example.com/?a=1&amp;b=2'>&#x65E5;&#x672C;&#35486; &#x1F3B8; &amp;#12354;</A></DL></DL>"
        let page = try XCTUnwrap(LibraryTransfer.parse(Data(html.utf8), kind: .favorites).first)
        XCTAssertEqual(page.title, "日本語 🎸 &#12354;")
        XCTAssertEqual(page.folders, ["お気に入り"])
        XCTAssertEqual(page.url.absoluteString, "https://example.com/?a=1&b=2")
    }
    func testUTF16SafariImportAndMalformedEncodingDoesNotSilentlyCorrupt() throws {
        let html = "<DL><A HREF='https://example.com'>日本語 🎸</A></DL>"
        let data = try XCTUnwrap(html.data(using: .utf16))
        XCTAssertEqual(try LibraryTransfer.parse(data, kind: .favorites).first?.title, "日本語 🎸")
        XCTAssertThrowsError(try LibraryTransfer.parse(Data([0xFF, 0x80, 0x81]), kind: .bookmarks))
    }
    #if canImport(Darwin)
    func testDeclaredShiftJISImport() throws {
        let html = "<meta charset='Shift_JIS'><DL><A HREF='https://example.com'>日本語</A></DL>"
        let data = try XCTUnwrap(html.data(using: .shiftJIS))
        XCTAssertEqual(try LibraryTransfer.parse(data, kind: .favorites).first?.title, "日本語")
    }
    #endif
}
