import Foundation

enum DeploymentState: String, Codable, Sendable, CaseIterable {
    case queued = "QUEUED"
    case initializing = "INITIALIZING"
    case building = "BUILDING"
    case ready = "READY"
    case error = "ERROR"
    case canceled = "CANCELED"
    case blocked = "BLOCKED"

    var isInProgress: Bool {
        switch self {
        case .queued, .initializing, .building:
            true
        default:
            false
        }
    }

    var isTerminal: Bool {
        switch self {
        case .ready, .error, .canceled, .blocked:
            true
        default:
            false
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .initializing: "Initializing"
        case .building: "Building"
        case .ready: "Ready"
        case .error: "Error"
        case .canceled: "Canceled"
        case .blocked: "Blocked"
        }
    }

    var shortLabel: String {
        switch self {
        case .queued: "Q"
        case .initializing: "INIT"
        case .building: "BUILD"
        case .ready: "OK"
        case .error: "ERR"
        case .canceled: "CAN"
        case .blocked: "BLK"
        }
    }
}

struct DeploymentMeta: Codable, Sendable {
    let githubCommitMessage: String?
    let githubCommitRef: String?
    let githubCommitSha: String?
    let githubCommitAuthorName: String?
}

struct DeploymentCreator: Codable, Sendable {
    let username: String?
}

struct Deployment: Codable, Identifiable, Sendable {
    let uid: String
    let name: String
    let url: String?
    let state: DeploymentState?
    let readyState: DeploymentState?
    let target: String?
    let createdAt: TimeInterval?
    let buildingAt: TimeInterval?
    let ready: TimeInterval?
    let meta: DeploymentMeta?
    let creator: DeploymentCreator?

    var id: String { uid }

    var status: DeploymentState {
        readyState ?? state ?? .queued
    }

    var previewURL: URL? {
        guard let url, !url.isEmpty else { return nil }
        if url.hasPrefix("http") {
            return URL(string: url)
        }
        return URL(string: "https://\(url)")
    }

    var branch: String? {
        meta?.githubCommitRef
    }

    var commitMessage: String? {
        meta?.githubCommitMessage
    }

    var commitSHA: String? {
        meta?.githubCommitSha.map { String($0.prefix(7)) }
    }

    var isProduction: Bool {
        target?.lowercased() == "production"
    }

    var createdDate: Date? {
        guard let createdAt else { return nil }
        return Date(timeIntervalSince1970: createdAt / 1000)
    }

    var readyDate: Date? {
        guard let ready else { return nil }
        return Date(timeIntervalSince1970: ready / 1000)
    }

    /// Best available timestamp for when the deployment last completed or started.
    var deployedDate: Date? {
        readyDate ?? createdDate
    }

    var durationSeconds: TimeInterval? {
        guard let buildingAt else { return nil }
        let end = ready ?? Date().timeIntervalSince1970 * 1000
        return (end - buildingAt) / 1000
    }
}

struct DeploymentsResponse: Codable, Sendable {
    let deployments: [Deployment]
}

struct DeploymentDetailResponse: Codable, Sendable {
    let uid: String?
    let name: String?
    let url: String?
    let state: DeploymentState?
    let readyState: DeploymentState?
    let target: String?
    let createdAt: TimeInterval?
    let buildingAt: TimeInterval?
    let ready: TimeInterval?
    let meta: DeploymentMeta?
    let creator: DeploymentCreator?

    func asDeployment(fallbackID: String) -> Deployment {
        Deployment(
            uid: uid ?? fallbackID,
            name: name ?? "deployment",
            url: url,
            state: state,
            readyState: readyState,
            target: target,
            createdAt: createdAt,
            buildingAt: buildingAt,
            ready: ready,
            meta: meta,
            creator: creator
        )
    }
}
