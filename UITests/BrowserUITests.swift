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
        app.buttons["menuButton"].tap()
        app.buttons["新しいプライベートタブ"].tap()
        XCTAssertTrue(app.staticTexts["プライベートブラウズ"].waitForExistence(timeout: 5))
        app.buttons["tabsButton"].tap()
        XCTAssertTrue(app.navigationBars["タブ 2"].waitForExistence(timeout: 5))
    }

    func testSettingsCanBeReachedAndToolbarPositionChanged() {
        app.buttons["menuButton"].tap()
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        app.buttons["toolbarPositionPicker"].tap()
        app.buttons["上"].tap()
        app.navigationBars["設定"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["menuButton"].exists)
    }

    func testAddressBarRejectsExecutableScheme() {
        let field = app.textFields["addressField"]
        field.tap()
        app.buttons["入力を消去"].tap()
        field.typeText("javascript:alert(1)\n")
        XCTAssertTrue(app.alerts["お知らせ"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts["アドレス欄ではHTTP・HTTPSのURLを開けます。"].exists)
    }
}
