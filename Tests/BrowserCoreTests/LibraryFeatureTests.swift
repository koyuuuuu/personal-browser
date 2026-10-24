import XCTest
@testable import BrowserCore

final class LibraryFeatureTests: XCTestCase {
    func testFiveHundredTabsSurviveSaveValidation() throws {
        var snapshot = BrowserSnapshot()
        snapshot.session.tabs = (0..<501).map { TabRecord(url: URL(string: "https://example.com/\($0)")) }
        snapshot.session.selectedID = snapshot.session.tabs[499].id
        let result = try snapshot.validated()
        XCTAssertEqual(result.session.tabs.count, 500)
        XCTAssertEqual(result.session.selectedID, snapshot.session.selectedID)
    }
    func testFolderCyclesRejectedAndRemovingFolderPreservesContents() throws {
        var extras = LibraryExtras()
        let parent = BookmarkFolder(name: "親"), child = BookmarkFolder(name: "子")
        extras.folders = [parent, BookmarkFolder(id: child.id, name: child.name, parentID: parent.id)]
        extras.bookmarkFolders["item"] = child.id
        XCTAssertFalse(extras.canMoveFolder(parent.id, to: child.id))
        extras.removeFolder(child.id)
        XCTAssertEqual(extras.bookmarkFolders["item"], parent.id)
        XCTAssertNoThrow(try extras.validated())
    }
    func testQuotedCSVAndPasswordIsolation() throws {
        let text = "title,url\r\n\"A, B\",https://example.com\r\n\"C\"\"D\",https://example.org\r\n"
        let pages = try LibraryTransfer.parse(Data(text.utf8), kind: .bookmarks)
        XCTAssertEqual(pages.map(\.title), ["A, B", "C\"D"])
        XCTAssertThrowsError(try LibraryTransfer.parse(Data("url,username,password\nhttps://example.com,a,secret".utf8), kind: .history))
        XCTAssertThrowsError(try LibraryTransfer.parse(Data("{\"logins\":[{\"url\":\"https://example.com\"}]}".utf8), kind: .bookmarks))
    }
    func testNetscapeHTMLPreservesFolderPathAndRejectsExecutableLinks() throws {
        let html = #"<DL><DT><H3>仕事</H3><DL><DT><A HREF="https://example.com/?a=1&amp;b=2">A &amp; B</A><DT><A HREF="javascript:alert(1)">Bad</A></DL></DL>"#
        let pages = try LibraryTransfer.parse(Data(html.utf8), kind: .bookmarks)
        XCTAssertEqual(pages.count, 1); XCTAssertEqual(pages[0].folders, ["仕事"])
        XCTAssertEqual(pages[0].title, "A & B"); XCTAssertEqual(pages[0].url.absoluteString, "https://example.com/?a=1&b=2")
    }
    func testChromeJSONAndOwnExportRoundTrip() throws {
        let chrome = #"{"roots":{"bookmark_bar":{"name":"バー","children":[{"name":"Example","url":"https://example.com"}]}}}"#
        XCTAssertEqual(try LibraryTransfer.parse(Data(chrome.utf8), kind: .bookmarks).first?.folders, ["バー"])
        let item = Bookmark(title: "Example", url: URL(string: "https://example.com")!)
        var extras = LibraryExtras(); let folder = BookmarkFolder(name: "保存先")
        extras.folders = [folder]; extras.bookmarkFolders[item.id.uuidString] = folder.id
        extras.favorites = [item]
        let data = try LibraryTransfer.export(bookmarks: [item], history: [], extras: extras)
        XCTAssertEqual(try LibraryTransfer.parse(data, kind: .bookmarks).first?.folders, ["保存先"])
        XCTAssertEqual(try LibraryTransfer.parse(data, kind: .favorites).first?.url, item.url)
    }
    func testBlockingExceptionsRespectDomainBoundaries() {
        var prefs = FeaturePreferences(); prefs.blockingExceptions = ["example.com"]
        XCTAssertFalse(prefs.shouldBlock(URL(string: "https://video.example.com")))
        XCTAssertTrue(prefs.shouldBlock(URL(string: "https://notexample.com")))
        prefs.blockAdvertisements = false
        XCTAssertFalse(prefs.shouldBlock(URL(string: "https://other.example")))
    }
    func testExternalApplicationURLEscapingAndPolicy() {
        let url = URL(string: "https://example.com/?a=1&b=2")!
        let external = ExternalApplication.firefox.destination(for: url)!
        XCTAssertEqual(URLComponents(url: external, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, url.absoluteString)
        XCTAssertNil(ExternalApplication.chrome.destination(for: URL(string: "javascript:alert(1)")!))
    }
    func testWatchHTMLPassesVideoURLWithoutQueryInjection() throws {
        let video = URL(string: "https://youtu.be/example?a=1&b=2")!
        let url = try WatchHTML.destination(address: "https://private.example/watch.html?url=old", video: video)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.count, 1); XCTAssertEqual(items[0].value, video.absoluteString)
        XCTAssertEqual(try WatchHTML.destination(address: "https://private.example", video: video).path, "/watch.html")
        XCTAssertThrowsError(try WatchHTML.destination(address: "http://private.example", video: video))
        XCTAssertNil(WatchHTML.youtubeURL(URL(string: "https://notyoutube.com/watch")!))
    }

    func testSafariArchiveSkipsPasswordFileAndChecksCRC() throws {
        let data = Data(base64Encoded: "UEsDBBQAAAAAAF2IWF2lS+UTNQAAADUAAAAOAAAAQm9va21hcmtzLmh0bWw8REw+PERUPjxBIEhSRUY9Imh0dHBzOi8vZXhhbXBsZS5jb20iPlNhZmFyaTwvQT48L0RMPlBLAwQUAAAAAABdiFhdzDBUyDwAAAA8AAAADQAAAFBhc3N3b3Jkcy5jc3Z1cmwscGFzc3dvcmQKaHR0cHM6Ly9zZWNyZXQuZXhhbXBsZSx0ZXN0LW5vdC1hLXJlYWwtcGFzc3dvcmRQSwECFAMUAAAAAABdiFhdpUvlEzUAAAA1AAAADgAAAAAAAAAAAAAAgAEAAAAAQm9va21hcmtzLmh0bWxQSwECFAMUAAAAAABdiFhdzDBUyDwAAAA8AAAADQAAAAAAAAAAAAAAgAFhAAAAUGFzc3dvcmRzLmNzdlBLBQYAAAAAAgACAHcAAADIAAAAAAA=")!
        let entries = try BrowserArchive.entries(in: data, kind: .bookmarks)
        XCTAssertEqual(entries.map(\.name), ["Bookmarks.html"])
        let contents = try BrowserArchive.contents(of: entries[0])
        XCTAssertEqual(try LibraryTransfer.parse(contents, kind: .bookmarks).first?.title, "Safari")
        XCTAssertThrowsError(try BrowserArchive.verify(Data("changed".utf8), entry: entries[0]))
    }
    func testSafariDeflatedZIPWithAppleCompression() throws {
        #if canImport(Compression)
        let data = Data(base64Encoded: "UEsDBBQAAAAIAF2IWF2lS+UTNgAAADUAAAAOAAAAQm9va21hcmtzLmh0bWyzcfGxs3EJsbNxVPAIcnWzVcooKSkottLXT61IzC3ISdVLzs9VsgtOTEssyrTRd7Sz0QdqAABQSwMEFAAAAAgAXYhYXcwwVMg4AAAAPAAAAA0AAABQYXNzd29yZHMuY3N2Ky3K0SlILC4uzy9K4cooKSkottLXL05NLkot0UutSMwtyEnVKUktLtHNyy/RTdQtSk3M0YWpBwBQSwECFAMUAAAACABdiFhdpUvlEzYAAAA1AAAADgAAAAAAAAAAAAAAgAEAAAAAQm9va21hcmtzLmh0bWxQSwECFAMUAAAACABdiFhdzDBUyDgAAAA8AAAADQAAAAAAAAAAAAAAgAFiAAAAUGFzc3dvcmRzLmNzdlBLBQYAAAAAAgACAHcAAADFAAAAAAA=")!
        let entries = try BrowserArchive.entries(in: data, kind: .bookmarks)
        XCTAssertEqual(entries.count, 1)
        let contents = try BrowserArchive.contents(of: entries[0])
        XCTAssertEqual(try LibraryTransfer.parse(contents, kind: .bookmarks).first?.title, "Safari")
        #else
        throw XCTSkip("Apple Compression is tested on macOS CI")
        #endif
    }

}
