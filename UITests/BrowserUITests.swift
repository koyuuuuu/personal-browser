import XCTest

final class BrowserUITests: XCTestCase {
    private var app: XCUIApplication!
    private static var launchFailure = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        if Self.launchFailure { throw XCTSkip("The initial browser controls failed to appear; see the first failure before spending more runner time") }
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
        let ready = app.textFields["addressField"].waitForExistence(timeout: 15)
        if !ready { Self.launchFailure = true }
        XCTAssertTrue(ready, "The initial browser address field must be accessible")
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
        XCTAssertTrue(app.staticTexts["内蔵ルールを準備しました"].waitForExistence(timeout: 10), "WebKit must compile the native filtering rules")
        let toggle = app.switches["adBlockingToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testAddressSwipeReturnsToPreviousTab() {
        tapMenuControl("menuButton"); app.buttons["新しいタブ"].tap()
        XCTAssertTrue(app.staticTexts["お気に入り"].waitForExistence(timeout: 5))
        app.textFields["addressField"].swipeRight()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["オフラインのテストページ"].waitForExistence(timeout: 5))
    }
    func testTabTileCanBeSwipedClosed() {
        tapMenuControl("menuButton"); app.buttons["新しいプライベートタブ"].tap()
        app.buttons["tabsButton"].tap()
        XCTAssertTrue(app.navigationBars["タブ 2"].waitForExistence(timeout: 5))
        let tile = app.buttons["新しいタブ、選択中"]
        XCTAssertTrue(tile.waitForExistence(timeout: 5)); tile.swipeLeft()
        XCTAssertTrue(app.navigationBars["タブ 1"].waitForExistence(timeout: 5))
        tapMenuControl("閉じる")
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["オフラインのテストページ"].waitForExistence(timeout: 5), "The remaining tab must still be selected after a swipe close")
    }

    private func navigate(_ address: String) {
        if app.buttons["showChromeButton"].exists { tapMenuControl("showChromeButton") }
        let field = app.textFields["addressField"]; XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        if app.buttons["入力を消去"].exists { app.buttons["入力を消去"].tap() }
        field.typeText(address + "\n")
    }
    private func relaunchPreservingData(extra: [String] = []) {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-keep-data", "--ui-no-fixture"] + extra; app.launch()
    }
    func testLandscapeChromeIsHiddenCompactAndRevealsOnReverseScroll() {
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(app.buttons["showChromeButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["addressField"].exists)
        tapMenuControl("showChromeButton")
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(app.buttons["hideChromeButton"].frame.height, 44)
        app.webViews.firstMatch.swipeUp()
        XCTAssertTrue(app.buttons["showChromeButton"].waitForExistence(timeout: 5))
        app.webViews.firstMatch.swipeDown()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
    }
    func testBarsCanBeHiddenAndRestoredInPortrait() {
        tapMenuControl("hideChromeButton")
        XCTAssertTrue(app.buttons["showChromeButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["addressField"].exists)
        tapMenuControl("showChromeButton")
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
    }
    func testNextSwipeAtEndCreatesTabAndOverviewPlusIsAtBottom() {
        app.textFields["addressField"].swipeLeft()
        XCTAssertTrue(app.staticTexts["お気に入り"].waitForExistence(timeout: 5))
        tapMenuControl("tabsButton")
        XCTAssertTrue(app.navigationBars["タブ 2"].waitForExistence(timeout: 5))
        let add = app.buttons["overviewNewTabButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); XCTAssertGreaterThan(add.frame.midY, app.windows.firstMatch.frame.midY)
        add.tap(); XCTAssertTrue(app.buttons["tabsButton"].waitForExistence(timeout: 5)); tapMenuControl("tabsButton")
        XCTAssertTrue(app.navigationBars["タブ 3"].waitForExistence(timeout: 5))
    }
    func testOverviewOpensAtLastActiveTab() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-many-tabs"]; app.launch()
        XCTAssertTrue(app.buttons["tabsButton"].waitForExistence(timeout: 10)); tapMenuControl("tabsButton")
        XCTAssertTrue(app.navigationBars["タブ 19"].waitForExistence(timeout: 5))
        let active = app.buttons["新しいタブ、選択中"]
        XCTAssertTrue(active.waitForExistence(timeout: 5)); XCTAssertTrue(active.isHittable)
        XCTAssertLessThan(active.frame.maxY, app.buttons["overviewNewTabButton"].frame.minY)
    }
    func testNormalPreviewSurvivesProcessRestartWithoutLoadingThePage() {
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["オフラインのテストページ"].waitForExistence(timeout: 10))
        tapMenuControl("menuButton"); app.buttons["新しいタブ"].tap(); tapMenuControl("tabsButton")
        let preview = app.buttons.matching(NSPredicate(format: "value == 'プレビューあり'")).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        relaunchPreservingData()
        XCTAssertTrue(app.buttons["tabsButton"].waitForExistence(timeout: 10)); tapMenuControl("tabsButton")
        XCTAssertTrue(preview.waitForExistence(timeout: 8))
        XCTAssertEqual(app.webViews.count, 0, "Cached previews must not instantiate background WebViews")
    }
    func testRememberedCertificateIsReusedAfterRestart() {
        navigate("https://127.0.0.1:18766/tls-remember")
        XCTAssertTrue(app.navigationBars["接続の確認"].waitForExistence(timeout: 15))
        let toggle = app.switches["rememberConnectionToggle"]
        XCTAssertEqual(toggle.value as? String, "0"); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        tapMenuControl("allowConnectionButton")
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Local connection /tls-remember"].waitForExistence(timeout: 10))
        relaunchPreservingData()
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Local connection /tls-remember"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["接続の確認"].exists)
    }
    func testUncheckedCertificateIsAskedAgainAfterRestart() {
        navigate("https://127.0.0.1:18766/tls-once")
        XCTAssertTrue(app.navigationBars["接続の確認"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.switches["rememberConnectionToggle"].value as? String, "0")
        tapMenuControl("allowConnectionButton")
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Local connection /tls-once"].waitForExistence(timeout: 10))
        relaunchPreservingData()
        XCTAssertTrue(app.navigationBars["接続の確認"].waitForExistence(timeout: 15))
        app.buttons["キャンセル"].tap()
    }
    func testPlainLocalHTTPServerIsOfferedAfterTLSFailure() {
        navigate("https://127.0.0.1:18765/plain")
        XCTAssertTrue(app.navigationBars["接続の確認"].waitForExistence(timeout: 15))
        let toggle = app.switches["rememberConnectionToggle"]
        XCTAssertEqual(toggle.value as? String, "0"); toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        tapMenuControl("allowConnectionButton")
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Local connection /plain"].waitForExistence(timeout: 10))
        navigate("127.0.0.1:18765/remembered-http")
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Local connection /remembered-http"].waitForExistence(timeout: 10))
        XCTAssertTrue((app.textFields["addressField"].value as? String)?.hasPrefix("http://") == true)
    }
    func testAudioCanContinueInBackgroundWithoutPiP() {
        navigate("http://127.0.0.1:18765/media")
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.buttons["Play test audio"].waitForExistence(timeout: 10)); page.buttons["Play test audio"].tap()
        // Poll a fresh, numbered JS sample: paused == false alone does not
        // prove that the media clock has started or continued in background.
        var sample = 0
        func readClock() -> (media: Double, wall: Double) {
            sample += 1
            page.buttons["Check audio state"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            let state = page.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Sample \(sample):")).firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: 5))
            let fields = state.label.split(separator: ":")
            XCTAssertEqual(fields.count, 6, state.label)
            XCTAssertEqual(fields.dropFirst().first.map(String.init), "Playing", state.label)
            print("Audio clock sample: \(state.label)")
            guard fields.count == 6, let media = Double(fields[2]),
                  let wall = Double(fields[5].split(separator: "=").last ?? "") else {
                XCTFail("Invalid audio clock sample: \(state.label)"); return (-1, -1)
            }
            return (media, wall / 1000)
        }
        var before = readClock()
        for _ in 0..<6 {
            if before.media >= 1 { break }
            let tick = expectation(description: "Wait for media clock to start")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { tick.fulfill() }; wait(for: [tick], timeout: 3)
            before = readClock()
        }
        XCTAssertGreaterThanOrEqual(before.media, 1, "The audio fixture must actually start before backgrounding")
        XCUIDevice.shared.press(.home)
        let elapsed = expectation(description: "Audio runs while the app is backgrounded")
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { elapsed.fulfill() }; wait(for: [elapsed], timeout: 6)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        // XCUITest's activation returns before SpringBoard's zoom animation.
        // Run 19 recorded a 349x759 animated window and a displaced tap, even
        // though the settled accessibility frame was 402x874. Let it settle.
        let restored = expectation(description: "SpringBoard activation animation has finished")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { restored.fulfill() }; wait(for: [restored], timeout: 3)
        let after = readClock()
        let wallElapsed = after.wall - before.wall
        XCTAssertGreaterThanOrEqual(wallElapsed, 4)
        XCTAssertGreaterThanOrEqual(after.media - before.media, wallElapsed - 1,
                                   "Media time must follow wall time across backgrounding, without PiP")
    }

    func testAddressSideActionsAndTabSizeCanBeConfigured() {
        tapMenuControl("menuButton"); app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5)); tapMenuControl("presentationSettingsLink")
        XCTAssertTrue(app.navigationBars["表示・操作"].waitForExistence(timeout: 5))
        let stepper = app.steppers["tabColumnsStepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        stepper.buttons["tabColumnsStepper-Increment"].tap()
        XCTAssertTrue(stepper.label.contains("3列") || app.staticTexts["タブ一覧：3列"].waitForExistence(timeout: 5))
        let add = app.buttons["addAddressLeftButton"]
        for _ in 0..<4 { if add.exists && add.isHittable { break }; app.swipeUp() }
        tapMenuControl("addAddressLeftButton")
        XCTAssertTrue(app.buttons["ページ内を検索"].waitForExistence(timeout: 5))
        app.buttons["ページ内を検索"].tap()
        app.navigationBars["表示・操作"].buttons["設定"].tap()
        app.navigationBars["設定"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["addressLeft-find"].waitForExistence(timeout: 5))
    }

}
