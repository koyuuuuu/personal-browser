import Foundation
import XCTest
@testable import BrowserCore

final class UpdateFeedTests: XCTestCase {
    private func feed(version: String, build: String) -> Data {
        Data("""
        {"apps":[{"bundleIdentifier":"local.personalbrowser.app","versions":[{"version":"\(version)","buildVersion":"\(build)","localizedDescription":"追加機能"}]}]}
        """.utf8)
    }

    func testVersionsCompareNumericallyAndBuildsDetectSameVersionUpdates() throws {
        let current = AppBuild(version: "0.2.0", build: "7")!
        XCTAssertEqual(try UpdateFeed.available(in: feed(version: "0.2.0", build: "8"), current: current)?.buildVersion, "8")
        XCTAssertNotNil(try UpdateFeed.available(in: feed(version: "0.10.0", build: "1"), current: current))
        XCTAssertNil(try UpdateFeed.available(in: feed(version: "0.2.0", build: "7"), current: current))
        XCTAssertNil(try UpdateFeed.available(in: feed(version: "0.1.0", build: "99"), current: current))
    }

    func testInvalidOrUnrelatedFeedsDoNotAdvertiseAnUpdate() {
        let current = AppBuild(version: "0.2.0", build: "7")!
        XCTAssertThrowsError(try UpdateFeed.available(in: Data("{\"apps\":[]}".utf8), current: current))
        XCTAssertThrowsError(try UpdateFeed.available(in: feed(version: "beta", build: "8"), current: current))
        XCTAssertThrowsError(try UpdateFeed.available(in: Data(repeating: 32, count: 1_048_577), current: current))
    }

    func testSourceURLRequiresHTTPSAndRejectsEmbeddedCredentials() throws {
        XCTAssertEqual(try UpdateFeed.sourceURL(" https://example.com/k/secret/source.json ").host, "example.com")
        for value in ["http://example.com/source.json", "https://name:password@example.com/source.json", "file:///source.json", "https://example.com/source.json#fragment"] {
            XCTAssertThrowsError(try UpdateFeed.sourceURL(value))
        }
    }
}
