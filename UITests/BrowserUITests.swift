import XCTest

final class BrowserUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 15))
    }

    override func tearDownWithError() throws {
        if let run = testRun, run.failureCount > 0 {
            print("UI failure accessibility tree:\n\(app.debugDescription)")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testWebKitRendersAndExecutesOfflinePage() {
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 15))
        let button = page.buttons["ページ内ボタン"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        button.tap()
        XCTAssertTrue(page.staticTexts["操作成功"].waitForExistence(timeout: 5))
    }

    func testNewTabAndPrivateMode() {
        tapMenuControl("menuButton")
        app.buttons["新しいプライベートタブ"].tap()
        XCTAssertTrue(app.staticTexts["プライベートブラウズ"].waitForExistence(timeout: 5))
        app.buttons["tabsButton"].tap()
        XCTAssertTrue(app.navigationBars["タブ 2"].waitForExistence(timeout: 5))
    }

    func testSettingsCanBeReachedAndToolbarPositionChanged() {
        tapMenuControl("menuButton")
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        tapMenuControl("toolbarPositionPicker")
        app.buttons["上"].tap()
        app.navigationBars["設定"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["menuButton"].exists)
        XCTAssertLessThan(app.textFields["addressField"].frame.maxY, app.webViews.firstMatch.frame.minY)
    }

    func testAddressBarRejectsExecutableScheme() {
        let field = app.textFields["addressField"]
        field.tap()
        app.buttons["入力を消去"].tap()
        field.typeText("javascript:alert(1)\n")
        XCTAssertTrue(app.alerts["お知らせ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["アドレス欄ではHTTP・HTTPSのURLを開けます。"].exists)
    }

    private func tapMenuControl(_ identifier: String) {
        let control = app.buttons[identifier]
        XCTAssertTrue(control.waitForExistence(timeout: 5))
        // On Xcode 16.4 / iOS 18.5, SwiftUI Menu's accessibility wrappers
        // report no hit point, including their UIKit descendants. Screenshots
        // confirm the control is visible. Send a physical touch at its centre
        // and verify the resulting menu/action in the calling test.
        XCTAssertTrue(control.isEnabled)
        let frame = control.frame
        XCTAssertGreaterThan(frame.width, 0)
        XCTAssertGreaterThan(frame.height, 0)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(frame), "Menu must be inside the visible window")
        control.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    func testUpdateNotificationPreferenceCanBeTurnedOnAndOff() {
        tapMenuControl("menuButton")
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        tapMenuControl("updateSettingsLink")
        XCTAssertTrue(app.navigationBars["アプリの更新"].waitForExistence(timeout: 5))
        let toggle = app.switches["updateNotificationsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }
    func testShareSheetContainsActionsRatherThanBlankContent() {
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 10))
        tapMenuControl("menuButton")
        app.buttons["共有"].tap()
        let copy = app.cells.matching(NSPredicate(format: "label == 'Copy' OR label == 'コピー'")).firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10), "Share sheet must contain a copy action for the current page URL")
        copy.tap()
        tapMenuControl("menuButton"); app.buttons["共有"].tap()
        XCTAssertTrue(copy.waitForExistence(timeout: 10), "Sharing must work a second time")
    }

    func testFavoriteHomeAndBookmarkFolders() {
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["オフラインのテストページ"].waitForExistence(timeout: 10))
        tapMenuControl("menuButton"); app.buttons["ブックマークに追加"].tap()
        tapMenuControl("menuButton"); app.buttons["お気に入りに追加"].tap()
        tapMenuControl("menuButton"); app.buttons["ホーム"].tap()
        XCTAssertTrue(app.staticTexts["お気に入り"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["テストページ"].exists)
        app.buttons["bookmarksButton"].tap()
        XCTAssertTrue(app.navigationBars["ブックマーク"].waitForExistence(timeout: 5))
        tapMenuControl("createFolderButton")
        let alert = app.alerts["新しいフォルダ"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.tap(); alert.textFields.firstMatch.typeText("Saved")
        alert.buttons["作成"].tap()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 5))
    }

    func testAdBlockingCanBeConfigured() {
        tapMenuControl("menuButton"); app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        tapMenuControl("featureSettingsLink")
        XCTAssertTrue(app.navigationBars["ブラウザ機能"].waitForExistence(timeout: 5))
        let toggle = app.switches["adBlockingToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

}
