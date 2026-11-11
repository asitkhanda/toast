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

    // MARK: Cloudflare Pages

    private func cloudflareDeployment(_ json: String) throws -> CloudflareDeployment {
        try JSONDecoder().decode(CloudflareDeployment.self, from: Data(json.utf8))
    }

    func testCloudflareSuccessfulDeployIsReady() throws {
        let deployment = try cloudflareDeployment("""
        {"id":"d1","url":"https://abc.my-site.pages.dev","environment":"production",
         "created_on":"2026-11-11T10:00:00.123Z","project_name":"my-site",
         "latest_stage":{"name":"deploy","status":"success","started_on":"2026-11-11T10:01:00Z","ended_on":"2026-11-11T10:02:00Z"},
         "stages":[
           {"name":"queued","status":"success"},
           {"name":"initialize","status":"success"},
           {"name":"clone_repo","status":"success"},
           {"name":"build","status":"success","started_on":"2026-11-11T10:00:30Z","ended_on":"2026-11-11T10:01:00Z"},
           {"name":"deploy","status":"success","started_on":"2026-11-11T10:01:00Z","ended_on":"2026-11-11T10:02:00Z"}],
         "deployment_trigger":{"metadata":{"branch":"main","commit_hash":"abcdef123456","commit_message":"Ship it"}}}
        """)

        XCTAssertEqual(deployment.state, .ready)
        let mapped = deployment.asDeployment(fallbackName: "fallback")
        XCTAssertEqual(mapped.status, .ready)
        XCTAssertTrue(mapped.isProduction)
        XCTAssertEqual(mapped.branch, "main")
        XCTAssertEqual(mapped.commitSHA, "abcdef1")
        XCTAssertEqual(mapped.commitMessage, "Ship it")
        XCTAssertNotNil(mapped.createdDate)
        XCTAssertNotNil(mapped.readyDate)
        XCTAssertEqual(try XCTUnwrap(mapped.durationSeconds), 90, accuracy: 0.5)
    }

    func testCloudflareStageMapping() throws {
        func state(_ name: String, _ status: String) throws -> DeploymentState {
            try cloudflareDeployment("""
            {"id":"d","latest_stage":{"name":"\(name)","status":"\(status)"},"stages":[]}
            """).state
        }

        XCTAssertEqual(try state("queued", "active"), .queued)
        XCTAssertEqual(try state("initialize", "active"), .initializing)
        XCTAssertEqual(try state("clone_repo", "active"), .initializing)
        XCTAssertEqual(try state("build", "active"), .building)
        XCTAssertEqual(try state("deploy", "active"), .building)
        XCTAssertEqual(try state("deploy", "success"), .ready)
        XCTAssertEqual(try state("build", "failure"), .error)
        XCTAssertEqual(try state("build", "canceled"), .canceled)
    }

    func testCloudflareFailureInEarlierStageWins() throws {
        let deployment = try cloudflareDeployment("""
        {"id":"d","latest_stage":{"name":"deploy","status":"idle"},
         "stages":[{"name":"build","status":"failure"},{"name":"deploy","status":"idle"}]}
        """)
        XCTAssertEqual(deployment.state, .error)
    }

    func testWatchedProjectDecodesLegacyVercelEntries() throws {
        let legacy = #"{"projectId":"prj_1","projectName":"web","teamId":"team_1"}"#
        let watched = try JSONDecoder().decode(WatchedProject.self, from: Data(legacy.utf8))
        XCTAssertEqual(watched.provider, .vercel)
        XCTAssertEqual(watched.id, "team_1:prj_1")

        let cloudflare = WatchedProject(projectId: "site", projectName: "site", teamId: "acc", provider: .cloudflare)
        XCTAssertNotEqual(cloudflare.id, WatchedProject(projectId: "site", projectName: "site", teamId: "acc").id)
    }

    func testCloudflareTokenSanitizing() {
        XCTAssertEqual(CloudflareAPIClient.sanitizedToken("  abc123\n"), "abc123")
        XCTAssertEqual(CloudflareAPIClient.sanitizedToken("Bearer abc123"), "abc123")
        XCTAssertEqual(CloudflareAPIClient.sanitizedToken("\"abc123\""), "abc123")
    }

    func testCloudflareProjectKindRoundTrip() {
        let pages = CloudflareProjectKind.id(.pages, name: "my-site")
        let worker = CloudflareProjectKind.id(.worker, name: "api:v2")
        XCTAssertEqual(CloudflareProjectKind(projectID: pages), .pages)
        XCTAssertEqual(CloudflareProjectKind(projectID: worker), .worker)
        XCTAssertEqual(CloudflareProjectKind.name(fromProjectID: worker), "api:v2")
        XCTAssertNil(CloudflareProjectKind(projectID: "plain-name"))
        XCTAssertEqual(CloudflareProjectKind.name(fromProjectID: "plain-name"), "plain-name")
    }

    func testCloudflareWorkerDeploymentIsReady() throws {
        let json = """
        {"id":"dep1","created_on":"2026-11-11T10:00:00Z","source":"api",
         "annotations":{"workers/message":"Fix bug"}}
        """
        let worker = try JSONDecoder().decode(CloudflareWorkerDeployment.self, from: Data(json.utf8))
        let deployment = worker.asDeployment(workerName: "api")
        XCTAssertEqual(deployment.status, .ready)
        XCTAssertEqual(deployment.commitMessage, "Fix bug")
        XCTAssertTrue(deployment.isProduction)
        XCTAssertNotNil(deployment.deployedDate)
    }
}
