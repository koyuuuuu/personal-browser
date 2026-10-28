import XCTest
@testable import BrowserCore

final class TabSelectionHistoryTests: XCTestCase {
    func testChronologicalBackAndForwardDoesNotToggleOnlyTheTwoMostRecentTabs() {
        let a = UUID(), b = UUID(), c = UUID()
        var history = TabSelectionHistory()
        for id in [a, b, a, c] { history.visit(id) }
        XCTAssertEqual(history.step(forward: false), a)
        XCTAssertEqual(history.step(forward: false), b)
        XCTAssertEqual(history.step(forward: false), a)
        XCTAssertNil(history.step(forward: false))
        XCTAssertEqual(history.step(forward: true), b)
        XCTAssertEqual(history.step(forward: true), a)
        XCTAssertEqual(history.step(forward: true), c)
        XCTAssertNil(history.step(forward: true))
    }
    func testSelectingAnotherTabAfterGoingBackStartsANewBranch() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        var history = TabSelectionHistory()
        [a,b,c].forEach { history.visit($0) }
        _ = history.step(forward: false)
        history.visit(d)
        XCTAssertEqual(history.entries, [a,b,d])
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.step(forward: false), b)
    }
    func testClosingTabsPreservesCursorAndSkipsCollapsedDuplicateVisits() {
        let a = UUID(), b = UUID(), c = UUID()
        var history = TabSelectionHistory()
        [a,b,a,c].forEach { history.visit($0) }
        _ = history.step(forward: false)
        history.retain(openIDs: [a,c])
        XCTAssertEqual(history.entries, [a,c])
        XCTAssertEqual(history.current, a)
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.step(forward: true), c)
        history.retain(openIDs: [])
        XCTAssertNil(history.current)
        XCTAssertFalse(history.canGoForward)
    }
    func testNewTabPlacementUsesItsOpenerInsteadOfAlwaysUsingTheEnd() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(TabInsertion.index(after: a, in: [a,b,c]), 1)
        XCTAssertEqual(TabInsertion.index(after: b, in: [a,b,c]), 2)
        XCTAssertEqual(TabInsertion.index(after: nil, in: [a,b,c]), 3)
        XCTAssertEqual(TabInsertion.index(after: UUID(), in: [a,b,c]), 3)
        XCTAssertEqual(TabInsertion.index(after: a, in: []), 0)
    }
    func testToolbarExtensionNeverWritesUnknownActionsIntoTheOldFile() throws {
        var full = ToolbarPreferences()
        full.main = [.previousViewedTab,.nextViewedTab,.newTab,.tabs]
        full.left = [.previousViewedTab]; full.right = [.nextViewedTab]
        let extended = ExtendedToolbarPreferences(full)
        let data = try JSONEncoder().encode(extended.legacy)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("ViewedTab"))
        XCTAssertEqual(extended.resolve(against: try JSONDecoder().decode(ToolbarPreferences.self, from: data)), full)
        var changedByOldApp = extended.legacy; changedByOldApp.main = [.share,.tabs]
        XCTAssertEqual(extended.resolve(against: changedByOldApp), changedByOldApp)
        XCTAssertTrue(AddressBarAction.allCases.contains(.previousViewedTab))
        XCTAssertTrue(AddressBarAction.allCases.contains(.nextViewedTab))
    }
}
