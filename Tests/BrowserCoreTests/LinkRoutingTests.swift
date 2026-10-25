import XCTest
@testable import BrowserCore

final class LinkRoutingTests: XCTestCase {
    func testIncomingURLPreservesNestedQueryFragmentPlusAndJapaneseExactlyOnce() throws {
        let target = try XCTUnwrap(URL(string: "https://example.com/日本語?q=C%2B%2B+code&next=https%3A%2F%2Fexample.org%2F%3Fa%3D1%26b%3D2#part"))
        let incoming = try XCTUnwrap(IncomingBrowserLink.make(target))
        XCTAssertEqual(try IncomingBrowserLink.destination(incoming), target)
        XCTAssertEqual(try IncomingBrowserLink.destination(URL(string: "mybrowser://open?url=http%3A%2F%2F192.168.1.120%3A3000%2F")!).absoluteString, "http://192.168.1.120:3000/")
    }
    func testIncomingURLRejectsExecutableCredentialsAmbiguityAndMalformedInput() {
        let invalid = ["mybrowser://open", "mybrowser://open?url=", "mybrowser://other?url=https://example.com", "mybrowser://open/path?url=https://example.com", "mybrowser://open?url=https://example.com&extra=1", "mybrowser://open?url=https://example.com&url=https://example.org", "mybrowser://open?url=javascript%3Aalert(1)", "mybrowser://open?url=file%3A%2F%2F%2Fetc%2Fhosts", "mybrowser://open?url=https%3A%2F%2Fuser%3Apass%40example.com", "mybrowser://open?url=https%3A%2F%2Fexample.com%3A65536", "mybrowser://open?url=https%253A%252F%252Fexample.com", "mybrowser://open?url=https%3A%2F%2Fexample.com%0A", "mybrowser://open?url=https://example.com#fragment", "https://open?url=https://example.com"]
        for value in invalid { XCTAssertThrowsError(try IncomingBrowserLink.destination(URL(string: value)!), value) }
    }
    func testApplicationChoiceIsScopedAndAliasesDoNotMatchImpostorDomains() throws {
        var preferences = LinkPreferences()
        preferences.preferApplication(true, for: URL(string: "https://x.com/a")!)
        XCTAssertTrue(preferences.opensApplication(URL(string: "https://mobile.twitter.com/b")!))
        XCTAssertFalse(preferences.opensApplication(URL(string: "https://x.com.evil.example/a")!))
        preferences.preferApplication(false, for: URL(string: "https://www.twitter.com/c")!)
        XCTAssertFalse(preferences.opensApplication(URL(string: "https://x.com/a")!))
        preferences.preferApplication(true, for: URL(string: "https://youtu.be/a")!)
        let loaded = try JSONDecoder().decode(LinkPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertTrue(loaded.opensApplication(URL(string: "https://m.youtube.com/watch?v=a")!))
    }
    func testSearchDisplayAndEditingKeepEngineWithoutDisguisingOtherSites() throws {
        let google = URL(string: "https://www.google.com/search?q=C%2B%2B+%E6%97%A5%E6%9C%AC%E8%AA%9E&source=hp")!
        XCTAssertEqual(SearchAddress.display(google), "C++ 日本語")
        let edited = try SearchAddress.submission("新しい検索", current: google, defaultEngine: .bing)
        XCTAssertEqual(SearchAddress.query(edited)?.text, "新しい検索")
        XCTAssertEqual(SearchAddress.query(edited)?.engine, .google)
        XCTAssertEqual(try SearchAddress.submission("https://example.org", current: google, defaultEngine: .bing).host, "example.org")
        for raw in ["https://www.google.com.evil.example/search?q=hidden", "https://example.com/search?q=hidden", "https://www.google.com/maps?q=tokyo"] {
            let url = URL(string: raw)!; XCTAssertEqual(SearchAddress.display(url), raw)
        }
        XCTAssertEqual(SearchAddress.display(URL(string: "https://www.bing.com/search?q=two+words")!), "two words")
        XCTAssertEqual(SearchAddress.display(URL(string: "https://duckduckgo.com/?q=hello")!), "hello")
    }
    func testRecoveryNeverReplaysFormsOrTreatsUnrelatedErrorsAsInterruptions() {
        XCTAssertTrue(BrowserNavigationPolicy.canReplay(method: "GET", hasBody: false))
        XCTAssertFalse(BrowserNavigationPolicy.canReplay(method: "POST", hasBody: false))
        XCTAssertFalse(BrowserNavigationPolicy.canReplay(method: "GET", hasBody: true))
        XCTAssertTrue(BrowserNavigationPolicy.isInterrupted(domain: "WebKitErrorDomain", code: 102))
        XCTAssertFalse(BrowserNavigationPolicy.isInterrupted(domain: "NSURLErrorDomain", code: 102))
    }
    func testSearchSuggestionProvidersPreserveQueriesAndBoundResponse() throws {
        XCTAssertFalse(SearchSuggestionPreferences().enabled)
        for engine in SearchEngine.allCases {
            let url = try XCTUnwrap(SearchSuggestions.endpoint("C++ 日本語 &", engine: engine))
            XCTAssertEqual(url.scheme, "https")
            let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertTrue(parts.queryItems!.contains { $0.value == "C++ 日本語 &" })
            XCTAssertNil(SearchSuggestions.endpoint("https://private.example/secret", engine: engine))
        }
        let data = Data(#"["b",["browser","browser","browser app","","browser ios"]]"#.utf8)
        XCTAssertEqual(try SearchSuggestions.parse(data, engine: .google), ["browser", "browser app", "browser ios"])
        XCTAssertEqual(try SearchSuggestions.parse(Data(#"[{"phrase":"日本語"}]"#.utf8), engine: .duckDuckGo), ["日本語"])
        XCTAssertTrue(try SearchSuggestions.parse(Data(repeating: 32, count: 65_537), engine: .bing).isEmpty)
    }
    func testFavoriteDragOrderingRoundTripsAndKeepsIdentity() throws {
        var library = LibraryExtras()
        library.favorites = (0..<4).map { Bookmark(title: "Site \($0)", url: URL(string: "https://example.com/\($0)")!) }
        let ids = library.favorites.map(\.id)
        library.moveFavorite(ids[0], onto: ids[2])
        XCTAssertEqual(library.favorites.map(\.id), [ids[1], ids[2], ids[0], ids[3]])
        library.moveFavorite(ids[3], onto: ids[1])
        XCTAssertEqual(library.favorites.map(\.id), [ids[3], ids[1], ids[2], ids[0]])
        library.moveFavorite(UUID(), onto: ids[0])
        XCTAssertEqual(try JSONDecoder().decode(LibraryExtras.self, from: JSONEncoder().encode(library)).validated(), library)
        XCTAssertEqual(library.schemaVersion, 1)
    }
}
