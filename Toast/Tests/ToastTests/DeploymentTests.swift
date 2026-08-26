import XCTest
@testable import Toast

final class DeploymentTests: XCTestCase {
    func testDeploymentStateClassification() {
        XCTAssertTrue(DeploymentState.building.isInProgress)
        XCTAssertTrue(DeploymentState.ready.isTerminal)
        XCTAssertTrue(DeploymentState.error.isTerminal)
        XCTAssertFalse(DeploymentState.ready.isInProgress)
    }

    func testDeploymentPrefersReadyStateAndBuildsPreviewURL() {
        let deployment = Deployment(
            uid: "dpl_123",
            name: "web",
            url: "preview.example.com",
            state: .building,
            readyState: .ready,
            target: "PRODUCTION",
            createdAt: nil,
            buildingAt: nil,
            ready: nil,
            meta: DeploymentMeta(
                githubCommitMessage: "Ship it",
                githubCommitRef: "main",
                githubCommitSha: "123456789",
                githubCommitAuthorName: nil
            ),
            creator: nil
        )

        XCTAssertEqual(deployment.status, .ready)
        XCTAssertEqual(deployment.commitSHA, "1234567")
        XCTAssertTrue(deployment.isProduction)
        XCTAssertEqual(deployment.previewURL?.absoluteString, "https://preview.example.com")
    }
}
