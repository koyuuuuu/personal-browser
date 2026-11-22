import XCTest
@testable import BrowserCore

final class BackgroundAudioTests: XCTestCase {
    func testRecoveryRequiresExactTransitionAndIsConsumedOnlyOnce() {
        var policy = BackgroundAudioRecovery()
        XCTAssertFalse(policy.consume(token: "a", now: 10, background: true))
        policy.arm(token: "a", now: 10)
        XCTAssertFalse(policy.consume(token: "other-document", now: 11, background: true))
        XCTAssertFalse(policy.consume(token: "a", now: 11, background: false))
        XCTAssertTrue(policy.consume(token: "a", now: 11, background: true))
        XCTAssertFalse(policy.consume(token: "a", now: 11.1, background: true))
    }
    func testPauseInterruptionExpiryAndNewForegroundTransition() {
        var policy = BackgroundAudioRecovery()
        policy.arm(token: "old", now: 10); policy.cancel()
        XCTAssertFalse(policy.consume(token: "old", now: 11, background: true))
        policy.arm(token: "new", now: 20)
        XCTAssertFalse(policy.consume(token: "new", now: 23.1, background: true))
        policy.arm(token: "next", now: 30)
        XCTAssertTrue(policy.consume(token: "next", now: 30.5, background: true))
    }
}
