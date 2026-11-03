import XCTest
@testable import BrowserCore

final class PageRecoveryTests: XCTestCase {
    func testTransientErrorsExcludeTrustPolicyCancellationAndAuthentication() {
        XCTAssertTrue(PageRecoveryPolicy.isTransient(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost))
        XCTAssertTrue(PageRecoveryPolicy.isTransient(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet))
        for code in [NSURLErrorCancelled, NSURLErrorServerCertificateUntrusted, NSURLErrorSecureConnectionFailed, NSURLErrorUserAuthenticationRequired] {
            XCTAssertFalse(PageRecoveryPolicy.isTransient(domain: NSURLErrorDomain, code: code))
        }
        XCTAssertFalse(PageRecoveryPolicy.isTransient(domain: "WebKitErrorDomain", code: NSURLErrorTimedOut))
    }
    func testRetryBudgetDoesNotLoopAndExplicitNavigationAllowsAnotherAttempt() {
        var policy = PageRecoveryPolicy()
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertTrue(policy.claim(method: "GET", hasBody: false, now: now))
        XCTAssertFalse(policy.claim(method: "GET", hasBody: false, now: now.addingTimeInterval(1)))
        XCTAssertFalse(policy.claim(method: "GET", hasBody: false, now: now.addingTimeInterval(59)))
        XCTAssertTrue(policy.claim(method: "HEAD", hasBody: false, now: now.addingTimeInterval(60)))
        policy.userNavigation()
        XCTAssertTrue(policy.claim(method: "GET", hasBody: false, now: now.addingTimeInterval(61)))
    }
    func testFormsAndRequestBodiesAreNeverAutomaticallyReplayed() {
        for (method, body) in [("POST", false), ("POST", true), ("PUT", false), ("GET", true)] {
            var policy = PageRecoveryPolicy()
            XCTAssertFalse(policy.claim(method: method, hasBody: body))
            XCTAssertTrue(policy.claim(method: "GET", hasBody: false), "Rejected unsafe requests must not consume a safe request's budget")
        }
    }
    func testNativeFingerEscapeIsIndependentOfContentOffsetButIgnoresNormalBottomBounce() {
        for y in [-50.0, 50.0] {
            XCTAssertTrue(ChromeRecoveryGesture.shouldReveal(startedHidden: true, x: 2, y: y, contentTravel: 0, scrollable: false, locked: false))
            XCTAssertTrue(ChromeRecoveryGesture.shouldReveal(startedHidden: true, x: 2, y: y, contentTravel: 0, scrollable: true, locked: true))
        }
        XCTAssertFalse(ChromeRecoveryGesture.shouldReveal(startedHidden: true, x: 0, y: -60, contentTravel: 0, scrollable: true, locked: false))
        XCTAssertFalse(ChromeRecoveryGesture.shouldReveal(startedHidden: true, x: 80, y: 30, contentTravel: 0, scrollable: false, locked: true))
        XCTAssertFalse(ChromeRecoveryGesture.shouldReveal(startedHidden: false, x: 0, y: 60, contentTravel: 0, scrollable: false, locked: true))
        XCTAssertFalse(ChromeRecoveryGesture.shouldReveal(startedHidden: true, x: .nan, y: 60, contentTravel: 0, scrollable: false, locked: true))
    }
    func testRedditAlternativePreservesPageWithoutMatchingImpostorHosts() throws {
        let original = URL(string: "https://www.reddit.com/r/ios/comments/abc/title/?sort=new#comment")!
        let alternative = try XCTUnwrap(BrowserSitePolicy.redditWebAlternative(original))
        XCTAssertEqual(alternative.absoluteString, "https://old.reddit.com/r/ios/comments/abc/title/?sort=new#comment")
        XCTAssertNil(BrowserSitePolicy.redditWebAlternative(URL(string: "https://reddit.com.evil.example/r/ios")))
        XCTAssertNil(BrowserSitePolicy.redditWebAlternative(URL(string: "https://old.reddit.com/r/ios")))
        XCTAssertNil(BrowserSitePolicy.redditWebAlternative(URL(string: "mybrowser://reddit.com/r/ios")))
    }
}
