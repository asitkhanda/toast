import XCTest
@testable import Toast

private final class StubProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [String: (Int, String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let (status, body) = Self.responses[path] ?? (404, "{}")
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CloudflareClientTests: XCTestCase {
    private func makeClient() -> CloudflareAPIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return CloudflareAPIClient(token: "test", session: URLSession(configuration: config))
    }

    func testListsPagesAndWorkers() async throws {
        StubProtocol.responses = [
            "/client/v4/accounts/acc/pages/projects": (200, """
            {"result":[],"success":true,"errors":[],"messages":[],
             "result_info":{"page":1,"per_page":10,"count":0,"total_count":0,"total_pages":0}}
            """),
            "/client/v4/accounts/acc/workers/scripts": (200, """
            {"result":[
              {"id":"aiswariyadotcom","tag":"t1","etag":"e","created_on":"2025-01-01T00:00:00Z","modified_on":"2026-10-01T00:00:00Z",
               "has_assets":true,"has_modules":true,"logpush":false,"compatibility_date":"2025-01-01",
               "routes":[{"id":"r","pattern":"aiswariya.com/*","zone_name":"aiswariya.com"}],
               "placement":{"mode":"smart"},"tail_consumers":null,"usage_model":"standard",
               "last_deployed_from":"dash","observability":{"enabled":true,"head_sampling_rate":1}},
              {"id":"asit-work","tag":"t2"}
            ],"success":true,"errors":[],"messages":[]}
            """),
        ]

        let listing = try await makeClient().listProjectsWithNotice(accountId: "acc")
        XCTAssertEqual(listing.projects.map(\.name), ["aiswariyadotcom", "asit-work"])
        XCTAssertEqual(listing.projects.first?.id, "worker:aiswariyadotcom")
        XCTAssertEqual(listing.notice, "Pages: 0 found · Workers: 2 found")
    }

    func testLatestWorkerDeployment() async throws {
        StubProtocol.responses = [
            "/client/v4/accounts/acc/workers/scripts/asit-work/deployments": (200, """
            {"result":{"deployments":[
              {"id":"d2","created_on":"2026-11-10T10:00:00.5Z","source":"wrangler",
               "strategy":"percentage","versions":[{"version_id":"v","percentage":100}],
               "annotations":{"workers/message":"Frosted glass","workers/triggered_by":"upload"}}]},
             "success":true,"errors":[],"messages":[],
             "result_info":{"page":1,"per_page":10,"count":1,"total_count":1,"total_pages":1}}
            """),
        ]
        let deployment = try await makeClient().latestDeployment(accountId: "acc", projectID: "worker:asit-work")
        XCTAssertEqual(deployment?.status, .ready)
        XCTAssertEqual(deployment?.commitMessage, "Frosted glass")
    }

    private func build(status: String, outcome: String?, created: String = "2026-11-10T09:18:00.738Z") throws -> CloudflareWorkerBuild {
        let outcomeJSON = outcome.map { "\"\($0)\"" } ?? "null"
        return try JSONDecoder().decode(CloudflareWorkerBuild.self, from: Data("""
        {"build_uuid":"b1","status":"\(status)","build_outcome":\(outcomeJSON),
         "created_on":"\(created)","running_on":"2026-11-10T09:18:02.985Z","stopped_on":"2026-11-10T09:18:34.887Z",
         "build_trigger_metadata":{"branch":"main","commit_hash":"0243f324f6e38d1a","commit_message":"Frosted glass\\n\\nCo-Authored-By: x","author":"A",
           "environment_variables":{"SECRET":{"is_secret":true,"value":null}}}}
        """.utf8))
    }

    func testBuildStateMapping() throws {
        XCTAssertEqual(try build(status: "queued", outcome: nil).state, .queued)
        XCTAssertEqual(try build(status: "initializing", outcome: nil).state, .initializing)
        XCTAssertEqual(try build(status: "running", outcome: nil).state, .building)
        XCTAssertEqual(try build(status: "stopped", outcome: "success").state, .ready)
        XCTAssertEqual(try build(status: "stopped", outcome: "fail").state, .error)
        XCTAssertEqual(try build(status: "stopped", outcome: "failure").state, .error)
        XCTAssertEqual(try build(status: "stopped", outcome: "canceled").state, .canceled)
    }

    func testBuildBecomesDeploymentWithFirstLineOfCommit() throws {
        let deployment = try build(status: "stopped", outcome: "success").asDeployment(workerName: "asit-work")
        XCTAssertEqual(deployment.status, .ready)
        XCTAssertEqual(deployment.commitMessage, "Frosted glass")
        XCTAssertEqual(deployment.branch, "main")
        XCTAssertEqual(deployment.commitSHA, "0243f32")
        XCTAssertNotNil(deployment.readyDate)
        XCTAssertEqual(try XCTUnwrap(deployment.durationSeconds), 31.9, accuracy: 0.2)
    }

    func testWorkerUsesNewestBuildWhenReadable() async throws {
        StubProtocol.responses = [
            "/client/v4/accounts/acc/builds/workers/tag1/builds": (200, """
            {"result":[
              {"build_uuid":"old","status":"stopped","build_outcome":"success","created_on":"2026-11-01T00:00:00Z"},
              {"build_uuid":"new","status":"running","build_outcome":null,"created_on":"2026-11-10T00:00:00Z"}],
             "success":true,"errors":[],"messages":[]}
            """),
        ]
        let deployment = try await makeClient().latestDeployment(accountId: "acc", projectID: "worker:w", workerTag: "tag1")
        XCTAssertEqual(deployment?.id, "new")
        XCTAssertEqual(deployment?.status, .building)
    }

    func testWorkerFallsBackToDeploymentsWithoutBuildAccess() async throws {
        StubProtocol.responses = [
            "/client/v4/accounts/acc/builds/workers/tag1/builds": (403, #"{"success":false,"errors":[{"message":"forbidden"}],"result":null}"#),
            "/client/v4/accounts/acc/workers/scripts/w/deployments": (200, """
            {"result":{"deployments":[{"id":"d1","created_on":"2026-11-10T10:00:00Z","annotations":{"workers/message":"Manual"}}]},"success":true,"errors":[],"messages":[]}
            """),
        ]
        let deployment = try await makeClient().latestDeployment(accountId: "acc", projectID: "worker:w", workerTag: "tag1")
        XCTAssertEqual(deployment?.id, "d1")
        XCTAssertEqual(deployment?.status, .ready)
    }

    func testWorkerWithNoBuildsFallsBackToDeployments() async throws {
        StubProtocol.responses = [
            "/client/v4/accounts/acc/builds/workers/tag1/builds": (200, #"{"result":[],"success":true,"errors":[],"messages":[]}"#),
            "/client/v4/accounts/acc/workers/scripts/w/deployments": (200, """
            {"result":{"deployments":[{"id":"d1","created_on":"2026-11-10T10:00:00Z"}]},"success":true,"errors":[],"messages":[]}
            """),
        ]
        let deployment = try await makeClient().latestDeployment(accountId: "acc", projectID: "worker:w", workerTag: "tag1")
        XCTAssertEqual(deployment?.id, "d1")
    }
}
