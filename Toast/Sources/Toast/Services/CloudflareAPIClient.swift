import Foundation

enum CloudflareAPIError: LocalizedError {
    case unauthorized
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case decodingFailed(Error)
    case network(Error)
    case invalidURL
    case api(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Invalid or expired Cloudflare token. Reconnect in Settings."
        case .forbidden:
            "This Cloudflare token is missing a permission. It needs Account Settings → Read plus Cloudflare Pages → Read and/or Workers Scripts → Read."
        case .notFound:
            "Cloudflare resource not found."
        case .rateLimited:
            "Cloudflare rate limit reached. Will retry shortly."
        case .serverError(let code):
            "Cloudflare server error (\(code))."
        case .decodingFailed:
            "Unexpected response from Cloudflare."
        case .network(let error):
            error.localizedDescription
        case .invalidURL:
            "Invalid API URL."
        case .api(let message):
            message
        }
    }
}

// MARK: - Response models

struct CloudflareEnvelope<T: Decodable>: Decodable {
    let success: Bool?
    let result: T?
    let errors: [CloudflareMessage]?
    let resultInfo: CloudflareResultInfo?

    enum CodingKeys: String, CodingKey {
        case success, result, errors
        case resultInfo = "result_info"
    }
}

struct CloudflareResultInfo: Decodable, Sendable {
    let page: Int?
    let perPage: Int?
    let totalCount: Int?
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case perPage = "per_page"
        case totalCount = "total_count"
        case totalPages = "total_pages"
    }
}

struct CloudflarePage<T: Decodable & Sendable>: Sendable {
    let items: [T]
    let info: CloudflareResultInfo?

    var hasMore: Bool {
        guard let info, let page = info.page else { return false }
        if let totalPages = info.totalPages { return page < totalPages }
        if let total = info.totalCount, let perPage = info.perPage, perPage > 0 {
            return page * perPage < total
        }
        return false
    }
}

struct CloudflareEmptyResult: Decodable {
    init(from decoder: Decoder) throws {}
}

struct CloudflareMessage: Decodable, Sendable {
    let code: Int?
    let message: String?
}

struct CloudflareAccount: Decodable, Sendable {
    let id: String
    let name: String?
}

struct CloudflarePagesProject: Decodable, Sendable {
    let name: String
}

struct CloudflareWorkerScript: Decodable, Sendable {
    let id: String
    /// Immutable script ID that the Workers Builds API is keyed by.
    let tag: String?
}

struct CloudflareBuildMetadata: Decodable, Sendable {
    let branch: String?
    let commitHash: String?
    let commitMessage: String?
    let author: String?

    enum CodingKeys: String, CodingKey {
        case branch, author
        case commitHash = "commit_hash"
        case commitMessage = "commit_message"
    }
}

/// One Workers Builds (Git-connected CI) run. Environment variables in the response are deliberately not decoded.
struct CloudflareWorkerBuild: Decodable, Sendable {
    let buildUUID: String
    let status: String?
    let buildOutcome: String?
    let createdOn: String?
    let runningOn: String?
    let stoppedOn: String?
    let metadata: CloudflareBuildMetadata?

    enum CodingKeys: String, CodingKey {
        case status
        case buildUUID = "build_uuid"
        case buildOutcome = "build_outcome"
        case createdOn = "created_on"
        case runningOn = "running_on"
        case stoppedOn = "stopped_on"
        case metadata = "build_trigger_metadata"
    }

    var state: DeploymentState {
        let outcome = buildOutcome?.lowercased()
        switch status?.lowercased() {
        case "stopped", "finished", "complete", "completed":
            switch outcome {
            case "success", "succeeded": return .ready
            case "canceled", "cancelled": return .canceled
            case nil: return .building
            default: return .error
            }
        case "queued", "pending": return .queued
        case "initializing": return .initializing
        default: return .building
        }
    }

    func asDeployment(workerName: String) -> Deployment {
        let resolved = state
        let message = metadata?.commitMessage?
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
        let hash = metadata?.commitHash.flatMap { $0.isEmpty ? nil : $0 }
        return Deployment(
            uid: buildUUID,
            name: workerName,
            url: nil,
            state: resolved,
            readyState: nil,
            target: nil,
            createdAt: CloudflareDeployment.milliseconds(from: createdOn),
            buildingAt: CloudflareDeployment.milliseconds(from: runningOn),
            ready: resolved.isTerminal ? CloudflareDeployment.milliseconds(from: stoppedOn) : nil,
            meta: DeploymentMeta(
                githubCommitMessage: message,
                githubCommitRef: metadata?.branch.flatMap { $0.isEmpty ? nil : $0 },
                githubCommitSha: hash,
                githubCommitAuthorName: metadata?.author
            ),
            creator: nil
        )
    }
}

struct CloudflareWorkerDeployments: Decodable, Sendable {
    let deployments: [CloudflareWorkerDeployment]
}

struct CloudflareWorkerDeployment: Decodable, Sendable {
    let id: String
    let createdOn: String?
    let source: String?
    let annotations: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, source, annotations
        case createdOn = "created_on"
    }

    func asDeployment(workerName: String) -> Deployment {
        let created = CloudflareDeployment.milliseconds(from: createdOn)
        return Deployment(
            uid: id,
            name: workerName,
            url: nil,
            state: .ready,
            readyState: nil,
            target: "production",
            createdAt: created,
            buildingAt: nil,
            ready: created,
            meta: DeploymentMeta(
                githubCommitMessage: annotations?["workers/message"],
                githubCommitRef: nil,
                githubCommitSha: nil,
                githubCommitAuthorName: nil
            ),
            creator: nil
        )
    }
}

struct CloudflareStage: Decodable, Sendable {
    let name: String?
    let status: String?
    let startedOn: String?
    let endedOn: String?

    enum CodingKeys: String, CodingKey {
        case name, status
        case startedOn = "started_on"
        case endedOn = "ended_on"
    }
}

struct CloudflareTriggerMetadata: Decodable, Sendable {
    let branch: String?
    let commitHash: String?
    let commitMessage: String?

    enum CodingKeys: String, CodingKey {
        case branch
        case commitHash = "commit_hash"
        case commitMessage = "commit_message"
    }
}

struct CloudflareTrigger: Decodable, Sendable {
    let metadata: CloudflareTriggerMetadata?
}

struct CloudflareDeployment: Decodable, Sendable {
    let id: String
    let url: String?
    let environment: String?
    let createdOn: String?
    let projectName: String?
    let latestStage: CloudflareStage?
    let stages: [CloudflareStage]?
    let deploymentTrigger: CloudflareTrigger?

    enum CodingKeys: String, CodingKey {
        case id, url, environment, stages
        case createdOn = "created_on"
        case projectName = "project_name"
        case latestStage = "latest_stage"
        case deploymentTrigger = "deployment_trigger"
    }

    /// Maps Cloudflare's build stages onto Toast's shared deployment states.
    var state: DeploymentState {
        let allStages = stages ?? []
        if allStages.contains(where: { $0.status == "failure" }) || latestStage?.status == "failure" {
            return .error
        }
        if allStages.contains(where: { $0.status == "canceled" }) || latestStage?.status == "canceled" {
            return .canceled
        }

        guard let latest = latestStage else { return .queued }
        switch (latest.name, latest.status) {
        case ("deploy", "success"):
            return .ready
        case ("queued", _):
            return .queued
        case ("initialize", _), ("clone_repo", _):
            return .initializing
        case ("build", _), ("deploy", _):
            return .building
        default:
            return .queued
        }
    }

    func asDeployment(fallbackName: String) -> Deployment {
        let buildStage = stages?.first(where: { $0.name == "build" })
        let deployStage = stages?.first(where: { $0.name == "deploy" })
        let resolvedState = state
        let finished = resolvedState == .ready ? deployStage?.endedOn ?? latestStage?.endedOn : nil

        return Deployment(
            uid: id,
            name: projectName ?? fallbackName,
            url: url,
            state: resolvedState,
            readyState: nil,
            target: environment,
            createdAt: Self.milliseconds(from: createdOn),
            buildingAt: Self.milliseconds(from: buildStage?.startedOn),
            ready: Self.milliseconds(from: finished),
            meta: DeploymentMeta(
                githubCommitMessage: deploymentTrigger?.metadata?.commitMessage,
                githubCommitRef: deploymentTrigger?.metadata?.branch,
                githubCommitSha: deploymentTrigger?.metadata?.commitHash,
                githubCommitAuthorName: nil
            ),
            creator: nil
        )
    }

    static func milliseconds(from iso8601: String?) -> TimeInterval? {
        guard let iso8601 else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        guard let date = withFraction.date(from: iso8601) ?? plain.date(from: iso8601) else {
            return nil
        }
        return date.timeIntervalSince1970 * 1000
    }
}

// MARK: - Client

struct CloudflareAPIClient: Sendable {
    let token: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func listAccounts() async throws -> [Team] {
        var accounts: [CloudflareAccount] = []
        var page = 1
        while true {
            let batch: CloudflarePage<CloudflareAccount> = try await getPage("/accounts", page: page)
            accounts += batch.items
            if batch.items.isEmpty || !batch.hasMore || page >= 20 { break }
            page += 1
        }
        return accounts.map { Team(id: $0.id, slug: nil, name: $0.name) }
    }

    /// Lists Pages projects and Workers. A token may only cover one of them, so one failing
    /// with "forbidden" is tolerated as long as the other works.
    func listProjects(accountId: String) async throws -> [Project] {
        try await listProjectsWithNotice(accountId: accountId).projects
    }

    /// Also returns a plain-language note about what was found or why a source was skipped.
    func listProjectsWithNotice(accountId: String) async throws -> (projects: [Project], notice: String?) {
        var projects: [Project] = []
        var failures: [Error] = []
        var notes: [String] = []

        do {
            let pages = try await listPagesProjects(accountId: accountId)
            projects += pages
            notes.append("Pages: \(pages.count) found")
        } catch {
            failures.append(error)
            notes.append("Pages: \(Self.reason(error))")
        }

        do {
            let workers = try await listWorkers(accountId: accountId)
            projects += workers
            notes.append("Workers: \(workers.count) found")
        } catch {
            failures.append(error)
            notes.append("Workers: \(Self.reason(error))")
        }

        if failures.count == 2, let first = failures.first { throw first }
        let sorted = projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return (sorted, notes.joined(separator: " · "))
    }

    private static func reason(_ error: Error) -> String {
        if case CloudflareAPIError.forbidden = error { return "token lacks permission" }
        return error.localizedDescription
    }

    private func listPagesProjects(accountId: String) async throws -> [Project] {
        var projects: [Project] = []
        var page = 1
        while true {
            let batch: CloudflarePage<CloudflarePagesProject> = try await getPage(
                "/accounts/\(accountId)/pages/projects",
                page: page
            )
            projects += batch.items.map {
                Project(
                    id: CloudflareProjectKind.id(.pages, name: $0.name),
                    name: $0.name,
                    accountId: accountId,
                    updatedAt: nil,
                    link: nil
                )
            }
            if batch.items.isEmpty || !batch.hasMore || page >= 20 { break }
            page += 1
        }
        return projects
    }

    private func listWorkers(accountId: String) async throws -> [Project] {
        let scripts: [CloudflareWorkerScript] = try await get("/accounts/\(accountId)/workers/scripts")
        return scripts.map {
            Project(
                id: CloudflareProjectKind.id(.worker, name: $0.id),
                name: $0.id,
                accountId: accountId,
                updatedAt: nil,
                link: nil
            )
        }
    }

    /// Maps each Worker name to its immutable script tag.
    func workerTags(accountId: String) async throws -> [String: String] {
        let scripts: [CloudflareWorkerScript] = try await get("/accounts/\(accountId)/workers/scripts")
        return Dictionary(scripts.compactMap { script in script.tag.map { (script.id, $0) } },
                          uniquingKeysWith: { first, _ in first })
    }

    /// `projectID` is `pages:<name>` or `worker:<name>`. For Workers, `workerTag` enables real build status.
    func latestDeployment(accountId: String, projectID: String, workerTag: String? = nil) async throws -> Deployment? {
        let name = CloudflareProjectKind.name(fromProjectID: projectID)
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name

        switch CloudflareProjectKind(projectID: projectID) ?? .pages {
        case .pages:
            let deployments: [CloudflareDeployment] = try await get(
                "/accounts/\(accountId)/pages/projects/\(encoded)/deployments"
            )
            let newest = deployments.max {
                (CloudflareDeployment.milliseconds(from: $0.createdOn) ?? 0)
                    < (CloudflareDeployment.milliseconds(from: $1.createdOn) ?? 0)
            }
            return newest?.asDeployment(fallbackName: name)
        case .worker:
            // Prefer Workers Builds (real queued/building/failed/success). Fall back to the
            // deployments list when the token can't read builds or the Worker has none.
            if let workerTag, let build = try await latestBuild(accountId: accountId, workerTag: workerTag) {
                return build.asDeployment(workerName: name)
            }
            let result: CloudflareWorkerDeployments = try await get(
                "/accounts/\(accountId)/workers/scripts/\(encoded)/deployments"
            )
            // The API lists the deployment currently serving traffic first.
            return result.deployments.first?.asDeployment(workerName: name)
        }
    }

    /// Newest Workers Build, or nil if builds aren't readable or the Worker isn't Git-connected.
    private func latestBuild(accountId: String, workerTag: String) async throws -> CloudflareWorkerBuild? {
        do {
            let builds: [CloudflareWorkerBuild] = try await get(
                "/accounts/\(accountId)/builds/workers/\(workerTag)/builds"
            )
            return builds.max {
                (CloudflareDeployment.milliseconds(from: $0.createdOn) ?? 0)
                    < (CloudflareDeployment.milliseconds(from: $1.createdOn) ?? 0)
            }
        } catch CloudflareAPIError.forbidden {
            return nil
        } catch CloudflareAPIError.notFound {
            return nil
        } catch CloudflareAPIError.api {
            return nil
        }
    }

    /// Succeeds only if the token can read both accounts and Pages projects.
    func validateToken() async throws -> TokenValidation {
        let accounts = try await listAccounts()
        guard let first = accounts.first else {
            throw CloudflareAPIError.api("This token can't see any Cloudflare accounts.")
        }
        _ = try await listProjects(accountId: first.id)
        let elevated = await hasBroaderAccess(accountId: first.id)
        return TokenValidation(scopeWarning: elevated ? Self.readOnlyRecommendation : nil)
    }

    static let readOnlyRecommendation =
        "This token can do more than Toast needs. For best security, limit it to Cloudflare Pages: Read, Workers Scripts: Read and Account Settings: Read."

    /// A token that can list API tokens is broader than read-only deployment monitoring needs.
    private func hasBroaderAccess(accountId: String) async -> Bool {
        await requestSucceeded("/accounts/\(accountId)/tokens")
    }

    // MARK: Networking

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await performGet(path, query: query)
            } catch let error as CloudflareAPIError {
                guard isRetryable(error), attempt < 2 else { throw error }
                guard !Task.isCancelled else { throw CancellationError() }
                attempt += 1
                try await Task.sleep(for: .milliseconds(attempt == 1 ? 500 : 1500))
            }
        }
    }

    /// Fetches one page without sending `per_page`, because Cloudflare rejects sizes some endpoints don't allow.
    private func getPage<T: Decodable & Sendable>(_ path: String, page: Int) async throws -> CloudflarePage<T> {
        var attempt = 0
        while true {
            do {
                let envelope: CloudflareEnvelope<[T]> = try await performEnvelopeGet(
                    path,
                    query: page > 1 ? ["page": String(page)] : [:]
                )
                return CloudflarePage(items: envelope.result ?? [], info: envelope.resultInfo)
            } catch let error as CloudflareAPIError {
                guard isRetryable(error), attempt < 2 else { throw error }
                guard !Task.isCancelled else { throw CancellationError() }
                attempt += 1
                try await Task.sleep(for: .milliseconds(attempt == 1 ? 500 : 1500))
            }
        }
    }

    private func makeRequest(_ path: String, query: [String: String]) -> URLRequest? {
        guard var components = URLComponents(string: "https://api.cloudflare.com/client/v4\(path)") else {
            return nil
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func requestSucceeded(_ path: String) async -> Bool {
        guard let request = makeRequest(path, query: [:]) else { return false }
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200 ..< 300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    private func performEnvelopeGet<T: Decodable>(_ path: String, query: [String: String]) async throws -> CloudflareEnvelope<T> {
        guard let request = makeRequest(path, query: query) else {
            throw CloudflareAPIError.invalidURL
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw CloudflareAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw CloudflareAPIError.network(URLError(.badServerResponse))
        }

        switch http.statusCode {
        case 200 ..< 300:
            break
        case 401:
            throw CloudflareAPIError.unauthorized
        case 403:
            throw CloudflareAPIError.forbidden
        case 404:
            throw CloudflareAPIError.notFound
        case 429:
            throw CloudflareAPIError.rateLimited
        case 400:
            throw CloudflareAPIError.api(Self.badRequestMessage(from: data))
        default:
            throw CloudflareAPIError.serverError(http.statusCode)
        }

        do {
            let envelope = try decoder.decode(CloudflareEnvelope<T>.self, from: data)
            if envelope.success == false {
                throw CloudflareAPIError.api(envelope.errors?.first?.message ?? "Cloudflare request failed.")
            }
            return envelope
        } catch let error as CloudflareAPIError {
            throw error
        } catch {
            throw CloudflareAPIError.decodingFailed(error)
        }
    }

    private func performGet<T: Decodable>(_ path: String, query: [String: String]) async throws -> T {
        let envelope: CloudflareEnvelope<T> = try await performEnvelopeGet(path, query: query)
        guard let result = envelope.result else {
            throw CloudflareAPIError.api(envelope.errors?.first?.message ?? "Cloudflare returned no data.")
        }
        return result
    }

    private static func badRequestMessage(from data: Data) -> String {
        let envelope = try? JSONDecoder().decode(CloudflareEnvelope<CloudflareEmptyResult>.self, from: data)
        let detail = envelope?.errors?.first?.message
        if detail?.contains("Authorization header") == true {
            return "Cloudflare rejected the token format. Paste only the API token itself (about 40 letters, numbers, - and _), without \"Bearer\", quotes, or the rest of the curl command."
        }
        return detail.map { "Cloudflare rejected the request: \($0)" } ?? "Cloudflare rejected the request (400)."
    }

    /// Pulls the bare token out of common copy-paste mistakes (a "Bearer " prefix, quotes, spaces).
    static func sanitizedToken(_ raw: String) -> String {
        var token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.lowercased().hasPrefix("bearer ") {
            token = String(token.dropFirst(7))
        }
        return token
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'`"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isRetryable(_ error: CloudflareAPIError) -> Bool {
        switch error {
        case .rateLimited, .serverError, .network:
            true
        default:
            false
        }
    }
}
