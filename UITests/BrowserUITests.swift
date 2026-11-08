import XCTest
import UIKit

final class BrowserUITests: XCTestCase {
    private var app: XCUIApplication!
    private static var launchFailure = false

    override func setUpWithError() throws {
        continueAfterFailure = false
        if Self.launchFailure { throw XCTSkip("Initial controls or the external-URL fixture failed; see the first failure before spending more runner time") }
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        if name.contains("testPasswordVaultImportsLocksAndFillsOnlyOnRequest") {
            app.launchArguments += ["--ui-no-fixture", "--ui-password-fixture"]
        }
        if name.contains("testPerSourceVolumeAndMuteUseIndependentRealPlayers") {
            app.launchArguments += ["--ui-no-fixture", "--ui-volume-fixture"]
        }
        if name.contains("testLockedViewportChromeAndBoundedRecovery") || name.contains("testAppPromotionSuppressionPreservesLoginAndCanBeDisabled") || name.contains("testPortraitForwardScrollHidesBarsAndBottomBounceDoesNotReveal") {
            app.launchArguments += ["--ui-no-fixture", "--ui-resilience-fixture"]
            if name.contains("testAppPromotion") { app.launchArguments += ["--ui-promotion-page"] }
            if name.contains("testPortraitForwardScroll") { app.launchArguments += ["--ui-normal-scroll-fixture"] }
        }
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

    func testPasswordVaultImportsLocksAndFillsOnlyOnRequest() {
        func reveal(_ button: XCUIElement, upward: Bool) {
            for _ in 0..<4 {
                // SwiftUI may call a partly clipped row hittable even when its
                // actual tap point is under the home indicator. Require the
                // whole button inside the content area before interacting.
                if button.exists {
                    let rect = button.frame, window = app.frame
                    if button.isHittable && rect.minY > window.minY + 110 && rect.maxY < window.maxY - 110 { return }
                }
                if upward { app.swipeUp() } else { app.swipeDown() }
            }
            XCTFail("The requested vault control must be fully visible")
        }
        XCTAssertTrue(app.staticTexts["Password fixture"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["passwordInputButton"].waitForExistence(timeout: 10), "A real DOM login form must be detected")
        app.buttons["passwordVaultFixtureButton"].tap()
        app.buttons["unlockPasswordVaultButton"].tap()
        let importButton = app.buttons["importPasswordFixtureButton"]
        reveal(importButton, upward: true); importButton.tap()
        let confirm = app.buttons["confirmPasswordImportButton"]
        reveal(confirm, upward: true); confirm.tap()
        let record = app.buttons["passwordRecord-127.0.0.1"]
        reveal(record, upward: false)
        XCTAssertEqual(app.buttons.matching(identifier: "passwordRecord-127.0.0.1").count, 1, "The import must actually be committed")
        // Duplicate import goes through the same parser/merge path.
        reveal(importButton, upward: false); importButton.tap()
        reveal(confirm, upward: true); confirm.tap()
        reveal(record, upward: false)
        XCTAssertEqual(app.buttons.matching(identifier: "passwordRecord-127.0.0.1").count, 1)
        let lock = app.buttons["lockPasswordVaultButton"]
        reveal(lock, upward: true); lock.tap()
        XCTAssertTrue(app.buttons["unlockPasswordVaultButton"].waitForExistence(timeout: 5))
        app.buttons["unlockPasswordVaultButton"].tap()
        let fill = app.buttons["fillSavedPasswordButton"]
        XCTAssertTrue(fill.waitForExistence(timeout: 5), "The encrypted vault must retain its record after locking and reopening")
        fill.tap()
        XCTAssertTrue(app.buttons["Check password fill"].waitForExistence(timeout: 5))
        app.buttons["Check password fill"].tap()
        XCTAssertTrue(app.staticTexts["Fields filled; not submitted"].waitForExistence(timeout: 5))
        app.buttons["passwordVaultFixtureButton"].tap()
        XCTAssertTrue(app.buttons["unlockPasswordVaultButton"].waitForExistence(timeout: 5))
    }

    func testLockedViewportChromeAndBoundedRecovery() {
        XCTAssertTrue(app.staticTexts["Locked viewport"].waitForExistence(timeout: 20))
        let field = app.textFields["addressField"]
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            for upward in [true, false] {
                if field.exists { app.buttons["hideChromeButton"].tap() }
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !field.exists }, object: nil)], timeout: 5), .completed)
                let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: upward ? 0.65 : 0.3))
                let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: upward ? 0.3 : 0.65))
                start.press(forDuration: 0.03, thenDragTo: end)
                XCTAssertTrue(field.waitForExistence(timeout: 8), "Actual finger input must restore bars even when touchmove is cancelled and the viewport cannot move")
            }
        }
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(field.waitForExistence(timeout: 8))
        app.buttons["hideChromeButton"].tap()
        app.buttons["simulatePageTerminationButton"].tap()
        let count = app.staticTexts["automaticPageRecoveryCount"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in count.label == "1" }, object: nil)], timeout: 10), .completed)
        XCTAssertTrue(app.staticTexts["Locked viewport"].waitForExistence(timeout: 10))
        XCTAssertTrue(field.exists, "Recovery must keep browser controls visible")
        app.buttons["loadUnavailablePageButton"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in count.label == "2" }, object: nil)], timeout: 15), .completed)
        let tabs = app.buttons["failedPageTabsButton"]
        XCTAssertTrue(tabs.waitForExistence(timeout: 10))
        XCTAssertTrue(field.exists)
        app.buttons["hideChromeButton"].tap(); XCTAssertTrue(field.exists, "A failed page must keep its escape controls")
        tabs.tap()
        XCTAssertTrue(app.navigationBars["タブ 1"].waitForExistence(timeout: 5))
    }

    func testAppPromotionSuppressionPreservesLoginAndCanBeDisabled() {
        XCTAssertTrue(app.staticTexts["Browser choice used"].waitForExistence(timeout: 20))
        app.buttons["Check compatibility"].tap()
        XCTAssertTrue(app.staticTexts["Promotion removed; content usable"].waitForExistence(timeout: 8))
        app.buttons["Underlying action"].tap()
        XCTAssertTrue(app.staticTexts["Underlying action worked"].exists)
        app.buttons["Show login"].tap()
        XCTAssertTrue(app.staticTexts["Login remains"].waitForExistence(timeout: 5))
        app.buttons["Close login"].tap()
        app.buttons["toggleAppPromotionFixtureButton"].tap()
        app.buttons["reloadResilienceFixtureButton"].tap()
        XCTAssertTrue(app.staticTexts["Use the Reddit app"].waitForExistence(timeout: 10), "Disabling the feature must preserve the original app prompt after reload")
        app.buttons["toggleAppPromotionFixtureButton"].tap()
        XCTAssertTrue(app.staticTexts["Browser choice used"].waitForExistence(timeout: 10))
        app.buttons["Check compatibility"].tap()
        XCTAssertTrue(app.staticTexts["Promotion removed; content usable"].waitForExistence(timeout: 8))
    }

    func testPerSourceVolumeAndMuteUseIndependentRealPlayers() {
        let openMixer = app.buttons["audioMixerFixtureButton"]
        XCTAssertTrue(app.buttons["Play first"].waitForExistence(timeout: 20))
        app.buttons["Play first"].tap(); app.buttons["Play second"].tap()
        openMixer.tap()
        let firstMute = app.switches["audioMute-1"], secondMute = app.switches["audioMute-2"]
        XCTAssertTrue(firstMute.waitForExistence(timeout: 8)); XCTAssertTrue(secondMute.exists)
        firstMute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in firstMute.value as? String == "1" }, object: nil)], timeout: 5), .completed)
        XCTAssertEqual(secondMute.value as? String, "0", "Muting one DOM player must not mute its sibling")
        firstMute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        var firstAppliedValue: String?
        for id in ["1", "2"] {
            let enable = app.buttons["enableAudioGain-" + id]
            if !enable.isHittable { app.swipeUp() }
            enable.tap()
            let confirm = app.buttons["読み直して再生して有効化"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            openMixer.tap()
            let slider = app.sliders["audioGain-" + id]
            XCTAssertTrue(slider.waitForExistence(timeout: 18), "Only successful CORS reloads may expose a gain slider")
            if !slider.isHittable { app.swipeUp() }
            slider.adjust(toNormalizedSliderPosition: id == "1" ? 0.25 : 0.75)
            let expected = id == "1" ? 25 : 75
            let applied = NSPredicate { _, _ in
                let text = slider.value as? String ?? ""
                let value = Int(text.replacingOccurrences(of: "%", with: "")) ?? -100
                return abs(value - expected) <= 3
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: applied, object: nil)], timeout: 6), .completed,
                           "Read back the actual GainNode parameter, not just the slider's requested value")
            if id == "1" { firstAppliedValue = slider.value as? String }
        }
        let firstGain = app.sliders["audioGain-1"]
        XCTAssertEqual(firstGain.value as? String, firstAppliedValue, "Changing the second source must preserve the first gain")
        app.navigationBars["音声ミキサー"].buttons["閉じる"].tap()
        app.buttons["Play third"].tap()
        openMixer.tap()
        app.swipeUp()
        XCTAssertTrue(app.buttons["enableAudioGain-3"].waitForExistence(timeout: 10), "Explicitly load the third player's metadata before enabling its CORS check")
        app.buttons["enableAudioGain-3"].tap()
        let confirm = app.buttons["読み直して再生して有効化"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        openMixer.tap()
        app.swipeUp()
        let failure = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "CORS・サイト側の制御などで有効化できませんでした。")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 18), "An actual CORS-denied media load must restore the old loader without routing to Web Audio")
        XCTAssertFalse(app.sliders["audioGain-3"].exists)
        app.buttons["resetAudioRouteButton"].tap()
        app.buttons["再読込して制御を解除"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !self.app.sliders["audioGain-1"].exists && !self.app.sliders["audioGain-2"].exists }, object: nil)], timeout: 10), .completed)
        app.navigationBars["音声ミキサー"].buttons["閉じる"].tap()
        XCTAssertTrue(app.buttons["Play first"].waitForExistence(timeout: 8))
    }

    func testConcurrentAudioPreferenceAndRealPlayersAcrossTabs() {
        var page = app.webViews.containing(.staticText, identifier: "Concurrent A").firstMatch
        func settings() {
            tapMenuControl("menuButton"); tapMenuControl("設定")
            tapMenuControl("audioMixingSettingsLink")
        }
        func progress() -> (Double, Double, Bool, Bool) {
            let value = page.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[0-9.]+,[0-9.]+,(true|false),(true|false)")).firstMatch.label
            let p = value.split(separator: ",").map(String.init)
            guard p.count == 4 else { return (0,0,false,false) }
            return (Double(p[0]) ?? 0,Double(p[1]) ?? 0,p[2] == "true",p[3] == "true")
        }
        func advance(first: Bool, second: Bool) {
            let start = progress()
            let condition = NSPredicate { _, _ in
                let p = progress()
                return p.2 == first && p.3 == second && (!first || p.0 > start.0 + 0.3) && (!second || p.1 > start.1 + 0.3)
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: condition, object: nil)], timeout: 8), .completed)
        }
        settings()
        let toggle = app.switches["concurrentAudioToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(toggle.value as? String, "1")
        app.navigationBars["音声の同時再生"].buttons["設定"].tap()
        tapMenuControl("閉じる")
        navigate("http://127.0.0.1:18765/concurrent-audio-a")
        let first = page.buttons["Play first"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        advance(first: true, second: false)
        page.buttons["Play second"].tap(); advance(first: true, second: true)
        tapMenuControl("menuButton"); tapMenuControl("新しいタブ")
        navigate("http://127.0.0.1:18765/concurrent-audio-b")
        page = app.webViews.containing(.staticText, identifier: "Concurrent B").firstMatch
        XCTAssertTrue(page.buttons["Play first"].waitForExistence(timeout: 10)); page.buttons["Play first"].tap(); advance(first: true, second: false)
        app.buttons["tabsButton"].tap(); app.buttons["Concurrent A"].tap()
        page = app.webViews.containing(.staticText, identifier: "Concurrent A").firstMatch
        advance(first: true, second: true)
        page.buttons["Pause first"].tap(); advance(first: false, second: true)
        page.buttons["Pause both"].tap()
        app.buttons["tabsButton"].tap(); app.buttons["Concurrent B"].tap()
        page = app.webViews.containing(.staticText, identifier: "Concurrent B").firstMatch
        advance(first: true, second: false)
        page.buttons["Pause both"].tap()
        XCUIDevice.shared.press(.home); relaunchPreservingData()
        settings(); XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); XCTAssertEqual(toggle.value as? String, "0")
    }

    func testSelectedTextSearchOpensAnAdjacentNewTab() {
        navigate("http://127.0.0.1:18765/selection-fixture")
        let select = app.webViews.buttons["Select sample text"]
        XCTAssertTrue(select.waitForExistence(timeout: 10)); select.tap()
        let search = app.buttons["selectedTextSearchButton"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Selection must reach the public fallback UI")
        search.tap()
        let field = app.textFields["addressField"]
        let expected = "日本語 C++ & # %2B"
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in field.value as? String == expected }, object: nil)], timeout: 5), .completed)
        app.buttons["tabsButton"].tap()
        XCTAssertTrue(app.navigationBars["タブ 2"].waitForExistence(timeout: 5))
        let original = app.buttons["Selection fixture"]
        XCTAssertTrue(original.exists, "Searching must retain the original tab")
    }

    func testOrdinaryLinkAndFormStayInBrowserWithoutFrameInterruption() {
        navigate("http://127.0.0.1:18765/navigation-fixture")
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.links["Browser link"].waitForExistence(timeout: 10))
        page.links["Browser link"].tap()
        XCTAssertTrue(page.staticTexts["Local connection /linked"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'フレームの読み込み' OR label CONTAINS 'Frame load interrupted'")).firstMatch.exists)
        navigate("http://127.0.0.1:18765/navigation-fixture")
        XCTAssertTrue(page.buttons["Submit POST"].waitForExistence(timeout: 10)); page.buttons["Submit POST"].tap()
        XCTAssertTrue(page.staticTexts["POST kept: value=one"].waitForExistence(timeout: 10))
    }

    private func openExternalFixture(_ name: String) {
        // XCUIApplication.open can launch without delivering its URL on this
        // SDK and always relaunches. simctl uses the real OS URL dispatch path.
        let finished = expectation(description: "System delivered external URL")
        URLSession.shared.dataTask(with: URL(string: "http://127.0.0.1:18765/test-open-" + name)!) { _, response, error in
            XCTAssertNil(error)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 204)
            finished.fulfill()
        }.resume()
        wait(for: [finished], timeout: 20)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.alerts.buttons.matching(NSPredicate(format: "label == 'Open' OR label == '開く'")).firstMatch
        let deadline = Date().addingTimeInterval(150)
        while Date() < deadline {
            if open.exists {
                open.tap()
                // Wait for the OS to finish launching with its URL context.
                // activate/launch can start a new process without that URL.
                XCTAssertTrue(app.wait(for: .runningForeground, timeout: 90))
            }
            if app.state == .runningForeground {
                if name == "invalid", app.alerts["お知らせ"].exists { return }
                let label = name == "cold" ? "Local connection /external-cold?a=1&b=2" : "Local connection /external-warm"
                if name != "invalid", app.webViews.staticTexts[label].exists { return }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        print("External dispatch failed; target state: \(app.state.rawValue); system UI: \(springboard.debugDescription)")
        XCTFail("The OS URL dispatch must display the requested destination or invalid-input alert")
    }
    func test00ExternalURLColdLaunchBackgroundAndInvalidInput() {
        // Run the OS-delivery prerequisite first and stop cascading UI work if
        // it leaves a system prompt or unavailable fixture behind.
        Self.launchFailure = true
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        openExternalFixture("cold")
        XCTAssertTrue(app.webViews.staticTexts["Local connection /external-cold?a=1&b=2"].waitForExistence(timeout: 15))
        XCUIDevice.shared.press(.home)
        openExternalFixture("warm")
        XCTAssertTrue(app.webViews.staticTexts["Local connection /external-warm"].waitForExistence(timeout: 15))
        app.buttons["tabsButton"].tap()
        XCTAssertTrue(app.navigationBars["タブ 3"].waitForExistence(timeout: 5))
        tapMenuControl("閉じる")
        openExternalFixture("invalid")
        XCTAssertTrue(app.alerts["お知らせ"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        app.buttons["tabsButton"].tap()
        XCTAssertTrue(app.navigationBars["タブ 3"].waitForExistence(timeout: 5))
        Self.launchFailure = false
    }

    func testFavoriteDragReordersAndSettingsEditsLatestDataAfterRestart() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-no-fixture", "--ui-home-background"]; app.launch()
        let favorites = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'favorite-'"))
        XCTAssertTrue(favorites.element(boundBy: 2).waitForExistence(timeout: 10))
        let first = favorites.element(boundBy: 0), third = favorites.element(boundBy: 2)
        let firstID = first.identifier, thirdID = third.identifier
        first.press(forDuration: 0.7, thenDragTo: third, withVelocity: .slow, thenHoldForDuration: 0.5)
        let moved = app.buttons[firstID], target = app.buttons[thirdID]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in moved.frame.minX > target.frame.minX }, object: nil)], timeout: 5), .completed)
        tapMenuControl("menuButton"); app.buttons["設定"].tap(); tapMenuControl("favoritesSettingsLink")
        let row = app.buttons["favoriteEditor-" + firstID.replacingOccurrences(of: "favorite-", with: "")]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let title = app.textFields["タイトル"]; XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.press(forDuration: 1.1)
        if app.menuItems["Select All"].exists { app.menuItems["Select All"].tap() }
        else if app.menuItems["すべてを選択"].exists { app.menuItems["すべてを選択"].tap() }
        else { title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (title.value as? String ?? "").count)) }
        title.typeText("Edited favorite")
        app.buttons["保存"].tap()
        XCUIDevice.shared.press(.home); app.terminate()
        app.launchArguments = ["--ui-testing", "--ui-keep-data", "--ui-no-fixture"]; app.launch()
        XCTAssertTrue(app.buttons[firstID].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[firstID].label.contains("Edited favorite"))
        XCTAssertGreaterThan(app.buttons[firstID].frame.minX, app.buttons[thirdID].frame.minX)
    }

    func testHomeSearchSuggestionsCanBeEnabledAndDisabled() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-no-fixture", "--ui-suggestion-fixture"]; app.launch()
        tapMenuControl("menuButton"); app.buttons["設定"].tap()
        let toggle = app.switches["searchSuggestionsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5)); XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.navigationBars["設定"].buttons["閉じる"].tap()
        let field = app.textFields["addressField"]; field.tap(); field.typeText("browser")
        XCTAssertTrue(app.buttons["searchCandidate-browser one"].waitForExistence(timeout: 5))
        app.buttons["searchCandidate-browser one"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (field.value as? String) == "browser one" }, object: nil)], timeout: 5), .completed)
        tapMenuControl("menuButton"); app.buttons["設定"].tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.navigationBars["設定"].buttons["閉じる"].tap()
        tapMenuControl("menuButton"); app.buttons["ホーム"].tap()
        field.tap(); field.typeText("hidden")
        XCTAssertFalse(app.otherElements["homeSearchSuggestions"].exists)
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
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        settlePresentation()
        app.buttons["入力を消去"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(["", "URLまたは検索語"].contains(field.value as? String ?? ""))
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
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-adblock-fixture"]; app.launch()
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.staticTexts["Blocking fixture ready"].waitForExistence(timeout: 90))
        let check = page.buttons["Check filtering"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in check.isEnabled }, object: nil)], timeout: 15), .completed, "An allowed control image must load before checking filtering")
        check.tap()
        XCTAssertTrue(page.staticTexts["Blocked and hidden"].waitForExistence(timeout: 5), "The bundled filters must block a real request and hide its ad slot")
        tapMenuControl("menuButton"); app.buttons["設定"].tap()
        tapMenuControl("featureSettingsLink")
        XCTAssertTrue(app.staticTexts["標準フィルターを適用できます"].waitForExistence(timeout: 15))
        tapMenuControl("blockingStrengthPicker")
        app.buttons["強力"].tap()
        XCTAssertTrue(app.staticTexts["強力フィルターを適用できます"].waitForExistence(timeout: 90), "Both profiles must compile in actual WebKit")
        let cosmetic = app.switches["cosmeticBlockingToggle"]
        XCTAssertTrue(cosmetic.exists); XCTAssertEqual(cosmetic.value as? String, "1")
        let toggle = app.switches["adBlockingToggle"]
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testNewTabPlacementAndViewedTabBackForward() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-tab-navigation-fixture"]; app.launch()
        XCTAssertTrue(app.webViews.staticTexts["Tab A fixture"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["addressLeft-previousViewedTab"].exists)
        XCTAssertTrue(app.buttons["addressRight-nextViewedTab"].exists)
        XCTAssertFalse(app.buttons["previousViewedTabButton"].isEnabled)
        tapMenuControl("menuButton")
        let menuNewTab = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != 'newTabButton'", "新しいタブ")).firstMatch
        XCTAssertTrue(menuNewTab.waitForExistence(timeout: 5)); menuNewTab.tap()
        app.buttons["tabsButton"].tap()
        let selectedBlank = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tabPreview-' AND label == %@", "新しいタブ、選択中")).firstMatch
        XCTAssertTrue(selectedBlank.waitForExistence(timeout: 5))
        let tabA = app.buttons["Tab A"]
        XCTAssertEqual(tabA.frame.minY, selectedBlank.frame.minY, accuracy: 2, "Menu-created tab must be next to A, not last after C")
        tabA.tap()
        app.webViews.links["Open child tab"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Tab child ready"].waitForExistence(timeout: 15))
        app.buttons["tabsButton"].tap()
        let child = app.buttons["Tab child、選択中"]
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Tab A"].frame.minY, child.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(app.buttons["Tab B"].frame.minY, child.frame.minY)
        app.buttons["Tab B"].tap()
        app.buttons["previousViewedTabButton"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Tab child ready"].waitForExistence(timeout: 5))
        app.buttons["previousViewedTabButton"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Tab A fixture"].waitForExistence(timeout: 5))
        app.buttons["nextViewedTabButton"].tap()
        XCTAssertTrue(app.webViews.staticTexts["Tab child ready"].waitForExistence(timeout: 5))
        app.buttons["nextViewedTabButton"].tap()
        XCTAssertTrue(app.staticTexts["お気に入り"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nextViewedTabButton"].isEnabled)
        // B has C to its right; the toolbar + must append after C.
        app.buttons["newTabButton"].tap(); app.buttons["tabsButton"].tap()
        XCTAssertTrue(selectedBlank.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Tab C"].frame.minY, selectedBlank.frame.minY, accuracy: 2)
        XCTAssertGreaterThan(selectedBlank.frame.minX, app.buttons["Tab C"].frame.minX)
        app.buttons["Tab C"].tap(); app.buttons["tabsButton"].tap()
        app.buttons["overviewNewTabButton"].tap(); app.buttons["tabsButton"].tap()
        XCTAssertTrue(selectedBlank.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(selectedBlank.frame.minY, app.buttons["Tab C"].frame.minY, "Overview + must append even when C is not last")
        app.buttons["完了"].tap()
        XCTAssertTrue(app.buttons["addressLeft-previousViewedTab"].exists)
        XCTAssertTrue(app.buttons["addressRight-nextViewedTab"].exists)
        XCUIDevice.shared.press(.home)
        relaunchPreservingData()
        XCTAssertTrue(app.buttons["previousViewedTabButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["previousViewedTabButton"].isEnabled, "Visit order is memory-only, not a restored private browsing trace")
        XCTAssertTrue(app.buttons["addressRight-nextViewedTab"].exists, "New toolbar choices must persist separately")
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
        if !app.textFields["addressField"].exists { app.swipeDown() }
        let field = app.textFields["addressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        // Keyboard animation moves bottom chrome. Tapping Clear before it
        // settles can hit the toolbar underneath on a slow hosted simulator.
        settlePresentation()
        let clear = app.buttons["入力を消去"]
        if clear.exists { clear.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText(address + "\n")
    }
    private func relaunchPreservingData(extra: [String] = []) {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-keep-data", "--ui-no-fixture"] + extra; app.launch()
    }
    func testLandscapeChromeIsHiddenCompactAndRevealsOnReverseScroll() {
        XCUIDevice.shared.orientation = .landscapeRight
        settlePresentation()
        XCTAssertFalse(app.buttons["showChromeButton"].exists)
        XCTAssertFalse(app.textFields["addressField"].exists)
        app.swipeDown()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(app.buttons["hideChromeButton"].frame.height, 44)
        app.webViews.firstMatch.swipeUp()
        XCTAssertFalse(app.buttons["showChromeButton"].exists)
        app.webViews.firstMatch.swipeDown()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
    }
    func testBarsCanBeHiddenAndRestoredInPortrait() {
        tapMenuControl("hideChromeButton")
        XCTAssertFalse(app.buttons["showChromeButton"].exists)
        XCTAssertFalse(app.textFields["addressField"].exists)
        app.swipeDown()
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
        XCTAssertLessThanOrEqual(active.frame.maxY, app.buttons["overviewNewTabButton"].frame.minY + 0.5)
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

    func testLandscapeSwipeKeepsControlsWorkingAndTilesStayInsideWindow() {
        XCUIDevice.shared.orientation = .landscapeRight
        settlePresentation()
        app.webViews.firstMatch.swipeDown()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
        app.textFields["addressField"].swipeLeft()
        XCTAssertTrue(app.staticTexts["お気に入り"].waitForExistence(timeout: 5))
        tapMenuControl("menuButton")
        app.buttons.matching(NSPredicate(format: "label == 'タブ一覧' AND identifier != 'addressRight-tabs' AND identifier != 'addressLeft-tabs' AND identifier != 'tabsButton'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["タブ 2"].waitForExistence(timeout: 5))
        for orientation in [UIDeviceOrientation.landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = orientation
            settlePresentation()
            let tiles = app.buttons.matching(NSPredicate(format: "value == 'プレビューあり' OR value == 'プレビューなし'"))
            XCTAssertGreaterThanOrEqual(tiles.count, 2)
            let window = app.windows.firstMatch.frame
            for tile in tiles.allElementsBoundByIndex {
                XCTAssertGreaterThanOrEqual(tile.frame.minX, window.minX)
                XCTAssertLessThanOrEqual(tile.frame.maxX, window.maxX)
            }
        }
    }

    func testLandscapeHomeWithCroppedBackgroundKeepsEveryChromeControlTappable() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-no-fixture", "--ui-home-background"]; app.launch()
        XCUIDevice.shared.orientation = .landscapeRight; settlePresentation()
        app.swipeDown()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
        tapMenuControl("menuButton")
        for _ in 0..<4 where !app.buttons["設定"].exists { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(app.buttons["設定"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["ダウンロード"].frame.minY, app.buttons["設定"].frame.minY)
        app.buttons["設定"].tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5))
        app.navigationBars["設定"].buttons["閉じる"].tap()
        let field = app.textFields["addressField"]
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("http://127.0.0.1:18765/home-controls\n")
        XCTAssertTrue(app.webViews.firstMatch.staticTexts["Local connection /home-controls"].waitForExistence(timeout: 10))
    }

    func testHistoryFoldersSupportSingleAndHalfDayDeletionAndAddressSuggestions() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-no-fixture", "--ui-library-fixture"]; app.launch()
        let field = app.textFields["addressField"]; field.tap(); field.typeText("alpha")
        let prediction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'addressSuggestion-'")).firstMatch
        XCTAssertTrue(prediction.waitForExistence(timeout: 5))
        XCTAssertTrue(prediction.label.contains("https://example.com/alpha"))
        tapMenuControl("menuButton"); app.buttons["履歴"].tap()
        let groups = app.buttons.matching(identifier: "historyPeriod")
        XCTAssertEqual(groups.count, 2)
        let morning = groups.matching(NSPredicate(format: "label CONTAINS '午前'")).firstMatch
        morning.tap()
        let entries = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyEntry-'")).allElementsBoundByIndex
        XCTAssertEqual(entries.count, 2)
        entries[0].swipeLeft(); app.buttons["削除"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyEntry-'")).count, 1)
        morning.swipeLeft(); app.buttons["まとめて削除"].tap()
        XCTAssertEqual(groups.count, 1)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'historyEntry-'")).firstMatch.exists)
    }

    func testZoomToolbarButtonsChangeByFivePercentAndPersist() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-no-fixture", "--ui-library-fixture"]; app.launch()
        app.buttons["zoomInButton"].tap(); app.buttons["zoomInButton"].tap(); app.buttons["zoomOutButton"].tap()
        tapMenuControl("menuButton"); app.buttons["設定"].tap(); tapMenuControl("presentationSettingsLink")
        XCTAssertTrue(app.staticTexts["ページの文字・表示倍率：105％"].waitForExistence(timeout: 5))
        app.navigationBars["表示・操作"].buttons["設定"].tap(); app.navigationBars["設定"].buttons["閉じる"].tap()
        relaunchPreservingData()
        XCTAssertTrue(app.buttons["zoomInButton"].waitForExistence(timeout: 5))
        tapMenuControl("menuButton"); app.buttons["設定"].tap(); tapMenuControl("presentationSettingsLink")
        XCTAssertTrue(app.staticTexts["ページの文字・表示倍率：105％"].waitForExistence(timeout: 5))
    }

    func testPortraitForwardScrollHidesBarsAndBottomBounceDoesNotReveal() {
        navigate("http://127.0.0.1:18765/scroll-fixture")
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.staticTexts["Scroll fixture"].waitForExistence(timeout: 10))
        for _ in 0..<4 { page.swipeUp() }
        XCTAssertFalse(app.textFields["addressField"].exists)
        settlePresentation()
        XCTAssertFalse(app.textFields["addressField"].exists, "Bottom bounce must not count as deliberate reverse scrolling")
        page.swipeDown()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
    }

    func testSwipeClosingGridReflowsAndRemainsUsableAfterRepeatedDeletions() {
        app.terminate(); app.launchArguments = ["--ui-testing", "--ui-many-tabs"]; app.launch()
        tapMenuControl("tabsButton")
        for remaining in stride(from: 18, through: 16, by: -1) {
            let tile = app.buttons.matching(NSPredicate(format: "value == 'プレビューなし' AND label CONTAINS '選択中'")).firstMatch
            XCTAssertTrue(tile.waitForExistence(timeout: 5)); tile.swipeLeft()
            XCTAssertTrue(app.navigationBars["タブ \(remaining)"].waitForExistence(timeout: 5))
        }
        app.buttons["overviewNewTabButton"].tap()
        XCTAssertTrue(app.textFields["addressField"].waitForExistence(timeout: 5))
        tapMenuControl("tabsButton")
        XCTAssertTrue(app.navigationBars["タブ 17"].waitForExistence(timeout: 5))
    }

    private func settlePresentation() {
        let ready = expectation(description: "Keyboard or rotation presentation has settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { ready.fulfill() }
        wait(for: [ready], timeout: 3)
    }

}
