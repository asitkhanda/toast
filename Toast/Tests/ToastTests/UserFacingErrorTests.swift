import XCTest
@testable import Toast

final class UserFacingErrorTests: XCTestCase {
    func testVercelUnauthorizedAsksToReplaceToken() {
        let error = UserFacingError.from(VercelAPIError.unauthorized)
        XCTAssertEqual(error.title, "Vercel didn't accept this token")
        XCTAssertEqual(error.action, .replaceToken)
        XCTAssertNotNil(error.nextStep)
    }

    func testCloudflareTokenFormatIsExplained() {
        let raw = CloudflareAPIError.api("Cloudflare rejected the token format. Paste only the API token itself")
        let error = UserFacingError.from(raw)
        XCTAssertEqual(error.title, "That doesn't look like a Cloudflare token")
        XCTAssertEqual(error.action, .replaceToken)
    }

    func testCloudflareForbiddenNamesThePermissions() {
        let error = UserFacingError.from(CloudflareAPIError.forbidden)
        XCTAssertTrue(error.nextStep?.contains("Account Settings") == true)
    }

    func testRateLimitNeedsNoAction() {
        let error = UserFacingError.from(VercelAPIError.rateLimited)
        XCTAssertNil(error.action)
        XCTAssertTrue(error.message.contains("automatically"))
    }

    func testNetworkErrorsAreFriendly() {
        let error = UserFacingError.from(CloudflareAPIError.network(URLError(.notConnectedToInternet)))
        XCTAssertEqual(error.title, "Can't reach Cloudflare")
        XCTAssertEqual(error.action, .retry)
    }

    func testUnknownErrorsStillGetATitleAndRetry() {
        struct Odd: Error {}
        let error = UserFacingError.from(Odd())
        XCTAssertEqual(error.title, "Something went wrong")
        XCTAssertEqual(error.action, .retry)
    }
}

final class StatusSummaryTests: XCTestCase {
    func testAllLive() {
        XCTAssertEqual(StatusSummary.make(states: [.ready, .ready, .ready], isDisconnected: false).headline, "All 3 projects are live")
        XCTAssertEqual(StatusSummary.make(states: [.ready], isDisconnected: false).headline, "Your project is live")
    }

    func testMixedStates() {
        let summary = StatusSummary.make(states: [.error, .building, .ready, .ready], isDisconnected: false)
        XCTAssertEqual(summary.headline, "1 failed, 1 building, 2 live")
        XCTAssertEqual(summary.spoken, "Toast: 1 failed, 1 building, 2 live.")
    }

    func testEmptyAndDisconnected() {
        XCTAssertEqual(StatusSummary.make(states: [], isDisconnected: false).headline, "No projects yet")
        XCTAssertEqual(StatusSummary.make(states: [.ready], isDisconnected: true).headline, "Not connected")
    }
}
