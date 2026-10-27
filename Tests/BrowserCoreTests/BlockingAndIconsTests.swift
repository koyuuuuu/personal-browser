import XCTest
@testable import BrowserCore

final class BlockingAndIconsTests: XCTestCase {
    func testSiteIconOriginNeverIncludesFavoriteQueryOrCredentials() throws {
        XCTAssertEqual(SiteIconPolicy.origin(URL(string: "https://example.com/private/page?token=private#part")!)?.absoluteString, "https://example.com/")
        XCTAssertNil(SiteIconPolicy.origin(URL(string: "https://user:password@example.com/")!))
        XCTAssertNil(SiteIconPolicy.origin(URL(string: "javascript:alert(1)")!))
        XCTAssertEqual(SiteIconPolicy.origin(URL(string: "http://192.168.1.120:3000/page")!)?.absoluteString, "http://192.168.1.120:3000/")
    }
    func testSiteIconHTMLDiscoversTouchIconsAndResolvesRelativePaths() {
        let origin = URL(string: "https://example.com/en/")!
        let html = "<link rel='shortcut icon' href='../favicon.ico'><link HREF=\"/touch.png?v=1&amp;b=2\" REL=\"apple-touch-icon\"><link rel=stylesheet href='/not-an-icon.css'>"
        XCTAssertEqual(SiteIconPolicy.candidates(in: html, origin: origin).map(\.absoluteString), ["https://example.com/touch.png?v=1&b=2", "https://example.com/favicon.ico"])
    }
    func testPublicSiteCannotUseIconsToProbeLocalNetworkOrDowngradeHTTPS() {
        let origin = URL(string: "https://example.com/")!
        XCTAssertFalse(SiteIconPolicy.permits(URL(string: "http://example.com/icon.png")!, from: origin))
        XCTAssertFalse(SiteIconPolicy.permits(URL(string: "https://127.0.0.1/icon.png")!, from: origin))
        XCTAssertTrue(SiteIconPolicy.permits(URL(string: "https://cdn.example.net/icon.png")!, from: origin))
    }
    func testBlockingManifestBoundsAndProfileSelection() throws {
        let hash = String(repeating: "a", count: 64)
        let manifest = """
        {"schema":1,"revision":"\(hash)","generatedAt":"2026-10-27T00:00:00Z","sourceArchive":"filter-sources-\(hash).zip","profiles":{"standard":[{"name":"network-\(hash).json","sha256":"\(hash)","size":5,"count":1,"kind":"network"}],"strong":[{"name":"network-\(hash).json","sha256":"\(hash)","size":5,"count":1,"kind":"network"}]}}
        """
        let decoded = try JSONDecoder().decode(BlockingManifest.self, from: Data(manifest.utf8))
        XCTAssertNoThrow(try decoded.validated())
        XCTAssertEqual(decoded.files(for: BlockingPreferences()).count, 1)
        var traversal = decoded
        traversal.profiles["strong"]?[0].name = "../../browser.json"
        XCTAssertThrowsError(try traversal.validated())
        var oversized = decoded
        oversized.profiles["standard"]?[0].size = 20 * 1024 * 1024
        XCTAssertThrowsError(try oversized.validated())
    }
    func testDownloadedRulesCannotSpecifyScriptExecution() throws {
        let data = Data("[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"execute-script\"}}]".utf8)
        let file = BlockingRuleFile(name: "unused", sha256: "unused", size: data.count, count: 1, kind: "network")
        XCTAssertThrowsError(try file.validate(data))
    }
}
