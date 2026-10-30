import XCTest
@testable import BrowserCore

final class TextSearchTests: XCTestCase {
    func testSelectionAndSharedTextPreserveJapaneseAndSpecialCharactersExactlyOnce() throws {
        let text = "日本語 C++ & # ? = %2B / 😀\n次の行"
        for engine in SearchEngine.allCases {
            let incoming = try TextSearch.incomingLink(text)
            let destination = try IncomingBrowserLink.destination(incoming, engine: engine)
            XCTAssertEqual(destination, try TextSearch.url(text, engine: engine))
            XCTAssertEqual(SearchAddress.query(destination)?.text, text)
            XCTAssertEqual(SearchAddress.query(destination)?.engine, engine)
        }
        let urlText = "https://example.com/?a=1&b=2"
        XCTAssertEqual(SearchAddress.query(try TextSearch.url(urlText))?.text, urlText)
        XCTAssertEqual(try IncomingBrowserLink.destination(IncomingBrowserLink.make(URL(string: urlText)!)!).absoluteString, urlText)
    }

    func testLongQueriesRoundTripWithoutTruncationAndInvalidInputsAreRejected() throws {
        for text in [String(repeating: "語", count: 5_000), String(repeating: "a", count: 16_384)] {
            let destination = try IncomingBrowserLink.destination(TextSearch.incomingLink(text))
            XCTAssertEqual(SearchAddress.query(destination)?.text, text)
        }
        XCTAssertThrowsError(try TextSearch.url(" \n\t "))
        XCTAssertThrowsError(try TextSearch.url(String(repeating: "a", count: 16_385)))
        for raw in ["mybrowser://search?text=", "mybrowser://search?text=one&text=two", "mybrowser://search?text=one&url=https://example.com", "mybrowser://search?url=one", "mybrowser://search/path?text=one", "mybrowser://search?text=one#two"] {
            XCTAssertThrowsError(try IncomingBrowserLink.destination(URL(string: raw)!), raw)
        }
    }

    func testGoogleIsInitialDefaultAndPreviouslySavedEngineIsPreserved() throws {
        XCTAssertEqual(BrowserSettings().searchEngine, .google)
        for engine in SearchEngine.allCases {
            var previous = BrowserSettings(); previous.searchEngine = engine
            let restored = try JSONDecoder().decode(BrowserSettings.self, from: JSONEncoder().encode(previous))
            XCTAssertEqual(restored, previous)
        }
    }
}
